import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

final class BackgroundCollectorSchedulingTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testNearClaudeCacheDeadlineWaitsAndFetchesOnceMore() async throws {
        for delay in [20.0, 60] {
            let old = Self.snapshot(at: Self.now.addingTimeInterval(-880))
            let fresh = Self.snapshot(at: Self.now.addingTimeInterval(delay))
            let scenario = Scenario(results: [
                .cached(old, nextRefreshAt: Self.now.addingTimeInterval(delay)),
                .fetched(fresh, nextRefreshAt: fresh.fetchedAt.addingTimeInterval(900))
            ])

            let result = try await scheduledFetch(scenario)

            guard case let .fetched(snapshot, _) = result else {
                XCTFail("Expected the reading after the short wait")
                continue
            }
            XCTAssertEqual(snapshot, fresh)
            let recorded = await scenario.recorded
            XCTAssertEqual(recorded.fetches, 2)
            XCTAssertEqual(recorded.delays, [delay])
        }
    }

    func testNearClaudeCooldownDeadlineWaitsBeforeRecheckingGate() async throws {
        let deadline = Self.now.addingTimeInterval(45)
        let fresh = Self.snapshot(at: deadline)
        let scenario = Scenario(results: [
            .deferred(ClaudeRefreshError.rateLimited(until: deadline), snapshot: nil, nextRefreshAt: deadline),
            .fetched(fresh)
        ])

        let result = try await scheduledFetch(scenario)

        guard case let .fetched(snapshot, _) = result else {
            return XCTFail("Expected a fresh reading after the cooldown deadline")
        }
        XCTAssertEqual(snapshot, fresh)
        let recorded = await scenario.recorded
        XCTAssertEqual(recorded.fetches, 2)
        XCTAssertEqual(recorded.delays, [45])
    }

    func testSecondDeferredResultDoesNotStartAnotherWaitOrFetch() async throws {
        let firstDeadline = Self.now.addingTimeInterval(10)
        let nextDeadline = Self.now.addingTimeInterval(30)
        let scenario = Scenario(results: [
            .cached(Self.snapshot(at: Self.now), nextRefreshAt: firstDeadline),
            .deferred(ClaudeRefreshError.tooSoon(until: nextDeadline), snapshot: nil, nextRefreshAt: nextDeadline)
        ])

        let result = try await scheduledFetch(scenario)

        guard case let .deferred(error, _, nextRefreshAt) = result,
              case .tooSoon = error as? ClaudeRefreshError else {
            return XCTFail("Expected to return the second shared-gate result")
        }
        XCTAssertEqual(nextRefreshAt, nextDeadline)
        let recorded = await scenario.recorded
        XCTAssertEqual(recorded.fetches, 2)
        XCTAssertEqual(recorded.delays, [10])
    }

    func testLongCooldownMissingDeadlineAndCodexDoNotWaitOrFetchAgain() async throws {
        let snapshot = Self.snapshot(at: Self.now)
        let nearDeadline = Self.now.addingTimeInterval(10)
        let longDeadline = Self.now.addingTimeInterval(1_800)
        let cases: [(UsageProvider, UsageFetchResult)] = [
            (.claude, .cached(snapshot, nextRefreshAt: Self.now.addingTimeInterval(60.001))),
            (.claude, .cached(snapshot, nextRefreshAt: Self.now)),
            (.claude, .cached(snapshot, nextRefreshAt: Self.now.addingTimeInterval(-1))),
            (.claude, .fetched(snapshot, nextRefreshAt: Self.now.addingTimeInterval(900))),
            (.claude, .fetched(snapshot)),
            (.claude, .deferred(ClaudeRefreshError.inProgress, snapshot: snapshot)),
            (.claude, .deferred(ClaudeRefreshError.rateLimited(until: longDeadline), snapshot: nil,
                               nextRefreshAt: longDeadline)),
            (.codex, .cached(snapshot, nextRefreshAt: nearDeadline)),
            (.codex, .deferred(ClaudeRefreshError.tooSoon(until: nearDeadline), snapshot: nil,
                              nextRefreshAt: nearDeadline))
        ]
        for (provider, initial) in cases {
            let scenario = Scenario(results: [initial])

            let result = try await scheduledFetch(scenario, provider: provider)

            XCTAssertEqual(result.nextRefreshAt, initial.nextRefreshAt)
            let recorded = await scenario.recorded
            XCTAssertEqual(recorded.fetches, 1)
            XCTAssertTrue(recorded.delays.isEmpty)
        }
    }

    func testCancelledSleepPropagatesWithoutAnotherFetch() async throws {
        let scenario = Scenario(results: [
            .cached(Self.snapshot(at: Self.now), nextRefreshAt: Self.now.addingTimeInterval(25))
        ], cancelsSleep: true)

        do {
            _ = try await scheduledFetch(scenario)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        let recorded = await scenario.recorded
        XCTAssertEqual(recorded.fetches, 1)
        XCTAssertEqual(recorded.delays, [25])
    }

    func testFetchFailurePropagatesWithoutSleeping() async throws {
        let scenario = Scenario(results: [])

        do {
            _ = try await scheduledFetch(scenario)
            XCTFail("Expected fetch failure")
        } catch FixtureError.noMoreResults {
        }

        let recorded = await scenario.recorded
        XCTAssertEqual(recorded.fetches, 1)
        XCTAssertTrue(recorded.delays.isEmpty)
    }

    private func scheduledFetch(
        _ scenario: Scenario,
        provider: UsageProvider = .claude
    ) async throws -> UsageFetchResult {
        try await BackgroundCollector.scheduledFetch(
            provider: provider,
            now: { Self.now },
            sleep: { try await scenario.sleep($0) },
            fetch: { try await scenario.fetch() }
        )
    }

    private static func snapshot(at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "claude", name: "Claude Code",
                window: UsageWindow(remainingPercent: 62, resetsAt: date.addingTimeInterval(18_000),
                                    durationMinutes: 300)
            ),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: date
        )
    }

    private actor Scenario {
        private let results: [UsageFetchResult]
        private let cancelsSleep: Bool
        private var fetchCount = 0
        private var delays: [TimeInterval] = []

        init(results: [UsageFetchResult], cancelsSleep: Bool = false) {
            self.results = results
            self.cancelsSleep = cancelsSleep
        }

        var recorded: (fetches: Int, delays: [TimeInterval]) { (fetchCount, delays) }

        func fetch() throws -> UsageFetchResult {
            let index = fetchCount
            fetchCount += 1
            guard index < results.count else { throw FixtureError.noMoreResults }
            return results[index]
        }

        func sleep(_ delay: TimeInterval) throws {
            delays.append(delay)
            if cancelsSleep { throw CancellationError() }
        }
    }

    private enum FixtureError: Error {
        case noMoreResults
    }
}
