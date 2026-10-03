import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class UsageRefreshTests: XCTestCase {
    func testCachedReadingRetainsAccountObservationAndDoesNotClaimFreshLogin() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let saved = context.snapshot()
        let monitor = context.monitor {
            .cached(saved, nextRefreshAt: saved.fetchedAt.addingTimeInterval(900))
        }

        let didFetch = await monitor.refresh(allowCredentialPrompt: true)

        XCTAssertFalse(didFetch)
        XCTAssertEqual(monitor.snapshot?.fetchedAt, saved.fetchedAt)
        XCTAssertEqual(monitor.snapshot?.accountEmail, "saved-account@example.test")
        XCTAssertEqual(monitor.samples.map(\.observedAt), [saved.fetchedAt])
        XCTAssertEqual(monitor.weeklyWidgetSnapshot?.fetchedAt, saved.fetchedAt)
        XCTAssertNotNil(monitor.refreshMessage)
        XCTAssertNil(monitor.errorMessage)
    }

    func testCooldownRestoresLastReadingAndExplainsWhenManualRefreshCanCheckAgain() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let saved = context.snapshot()
        let deadline = saved.fetchedAt.addingTimeInterval(1_800)
        let monitor = context.monitor {
            .deferred(ClaudeRefreshError.rateLimited(until: deadline), snapshot: saved)
        }

        let didFetch = await monitor.refresh(allowCredentialPrompt: true)

        XCTAssertFalse(didFetch)
        XCTAssertEqual(monitor.snapshot, saved)
        XCTAssertEqual(monitor.samples.count, 1)
        XCTAssertEqual(monitor.errorMessage, ClaudeRefreshError.rateLimited(until: deadline).localizedDescription)
        XCTAssertFalse(monitor.requiresLogin)
        XCTAssertNil(monitor.refreshMessage)
    }

    func testPersistedAuthenticationFailureKeepsSavedAccountLabeledAsLastReading() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let saved = context.snapshot()
        let monitor = context.monitor {
            .deferred(ClaudeRefreshError.failed(.unauthorized, until: saved.fetchedAt.addingTimeInterval(900)),
                      snapshot: saved)
        }

        let didFetch = await monitor.refresh()

        XCTAssertFalse(didFetch)
        XCTAssertTrue(monitor.requiresLogin)
        XCTAssertEqual(monitor.snapshot?.accountEmail, saved.accountEmail)
        XCTAssertNotNil(monitor.errorMessage)
    }

    func testProviderCadenceKeepsCodexIntervalAndUsesSharedClaudeSpacing() {
        XCTAssertEqual(UsageProvider.codex.refreshInterval, 600)
        XCTAssertEqual(UsageProvider.claude.refreshInterval, ClaudeUsageCoordinator.minimumInterval)
    }

    func testSuccessfulCollectorCacheClearsEarlierAuthenticationFailure() async throws {
        let context = try Context()
        defer { context.cleanUp() }
        let saved = context.snapshot()
        let recovered = context.snapshot(at: saved.fetchedAt.addingTimeInterval(900))
        let results = FetchResults([
            .deferred(ClaudeRefreshError.failed(.unauthorized, until: saved.fetchedAt), snapshot: saved),
            .cached(recovered, nextRefreshAt: recovered.fetchedAt.addingTimeInterval(900))
        ])
        let monitor = context.monitor { await results.next() }

        await monitor.refresh()
        XCTAssertTrue(monitor.requiresLogin)
        let didFetch = await monitor.refresh()

        XCTAssertFalse(didFetch)
        XCTAssertFalse(monitor.requiresLogin)
        XCTAssertNil(monitor.errorMessage)
        XCTAssertNotNil(monitor.refreshMessage)
    }

    private actor FetchResults {
        private var results: [UsageFetchResult]

        init(_ results: [UsageFetchResult]) { self.results = results }
        func next() -> UsageFetchResult { results.removeFirst() }
    }

    private struct Context {
        let name = "UsageRefreshTests.\(UUID().uuidString)"
        let directory: URL
        let defaults: UserDefaults
        let now = Date()

        init() throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        }

        func snapshot(at date: Date? = nil) -> UsageSnapshot {
            let date = date ?? now
            return UsageSnapshot(mainLimit: LimitReading(limitId: "claude", name: "Claude Code", window: UsageWindow(
                remainingPercent: 73, resetsAt: date.addingTimeInterval(86_400), durationMinutes: 10_080)),
                otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: date,
                accountEmail: "saved-account@example.test")
        }

        @MainActor func monitor(_ fetch: @escaping @Sendable () async -> UsageFetchResult) -> UsageMonitor {
            UsageMonitor(provider: .claude, defaults: defaults, historyDirectory: directory,
                         widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("widget"), provider: .claude),
                         fetchResult: { _ in await fetch() }, recoveryDelaysNanoseconds: [], startsAutomatically: false)
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
