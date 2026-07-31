//
//  UsageMonitorTests.swift
//  CodexLimitsTests
//
//  Created by Erfan on 1/8/26.
//

import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class UsageMonitorTests: XCTestCase {
    func testRecoveryClearsClientErrorAndPublishesFreshSnapshot() async throws {
        let expected = Self.snapshot(remainingPercent: 62)
        let source = SnapshotSequence(
            outcomes: [.clientError(.invalidResponse), .snapshot(expected)]
        )
        let context = try makeContext {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()

        XCTAssertNil(context.monitor.snapshot)
        XCTAssertNil(context.monitor.forecast)
        XCTAssertEqual(
            context.monitor.errorMessage,
            CodexClientError.invalidResponse.localizedDescription
        )
        XCTAssertFalse(context.monitor.isRefreshing)

        await context.monitor.refresh()

        XCTAssertEqual(context.monitor.snapshot, expected)
        XCTAssertEqual(
            context.monitor.samples,
            [
                UsageSample(
                    observedAt: expected.fetchedAt,
                    remainingPercent: 62,
                    resetsAt: expected.mainLimit.window.resetsAt
                )
            ]
        )
        XCTAssertNotNil(context.monitor.forecast)
        XCTAssertNil(context.monitor.errorMessage)
        XCTAssertFalse(context.monitor.isRefreshing)
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testFinalFailurePreservesLastGoodSnapshotAndHistory() async throws {
        let expected = Self.snapshot(remainingPercent: 74)
        let source = SnapshotSequence(
            outcomes: [.snapshot(expected), .clientError(.timedOut)]
        )
        let context = try makeContext {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        let samplesAfterSuccess = context.monitor.samples
        let forecastAfterSuccess = context.monitor.forecast

        await context.monitor.refresh()

        XCTAssertEqual(context.monitor.snapshot, expected)
        XCTAssertEqual(context.monitor.samples, samplesAfterSuccess)
        XCTAssertEqual(context.monitor.forecast, forecastAfterSuccess)
        XCTAssertEqual(
            context.monitor.errorMessage,
            CodexClientError.timedOut.localizedDescription
        )
        XCTAssertFalse(context.monitor.isRefreshing)
    }

    func testGenericFetchFailureUsesStableFallbackMessage() async throws {
        let source = SnapshotSequence(outcomes: [.genericError])
        let context = try makeContext {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()

        XCTAssertNil(context.monitor.snapshot)
        XCTAssertEqual(
            context.monitor.errorMessage,
            "Couldn’t read Codex usage. Try refreshing again."
        )
        XCTAssertFalse(context.monitor.isRefreshing)
    }

    func testOverlappingRefreshDoesNotStartAnotherFetch() async throws {
        let source = SuspendedSnapshotSource()
        let context = try makeContext {
            await source.fetch()
        }
        defer { context.cleanUp() }
        let expected = Self.snapshot(remainingPercent: 81)

        let firstRefresh = Task { await context.monitor.refresh() }
        await source.waitUntilStarted()

        await context.monitor.refresh()

        let fetchCountWhileSuspended = await source.fetchCount
        XCTAssertEqual(fetchCountWhileSuspended, 1)
        XCTAssertTrue(context.monitor.isRefreshing)

        await source.resume(with: expected)
        await firstRefresh.value

        XCTAssertEqual(context.monitor.snapshot, expected)
        XCTAssertFalse(context.monitor.isRefreshing)
    }

    func testStoredSnapshotSurvivesRelaunchAndFinalFetchFailure() async throws {
        let expected = Self.snapshot(remainingPercent: 53)
        let source = SnapshotSequence(
            outcomes: [.snapshot(expected), .clientError(.invalidResponse)]
        )
        let context = try makeContext {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()

        let relaunched = UsageMonitor(
            defaults: context.defaults,
            historyDirectory: context.historyDirectory,
            historyNow: { Self.fixtureNow },
            fetchUsage: { try await source.fetch() },
            startsAutomatically: false
        )

        XCTAssertEqual(relaunched.snapshot, expected)

        await relaunched.refresh()

        XCTAssertEqual(relaunched.snapshot, expected)
        XCTAssertEqual(relaunched.samples.count, 1)
        XCTAssertEqual(
            relaunched.errorMessage,
            CodexClientError.invalidResponse.localizedDescription
        )
        XCTAssertFalse(relaunched.isRefreshing)
    }

    private func makeContext(
        fetchUsage: @escaping @Sendable () async throws -> UsageSnapshot
    ) throws -> UsageMonitorTestContext {
        let suiteName = "UsageMonitorTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let historyDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        let monitor = UsageMonitor(
            defaults: defaults,
            historyDirectory: historyDirectory,
            historyNow: { Self.fixtureNow },
            fetchUsage: fetchUsage,
            startsAutomatically: false
        )
        return UsageMonitorTestContext(
            monitor: monitor,
            defaults: defaults,
            suiteName: suiteName,
            historyDirectory: historyDirectory
        )
    }

    private static func snapshot(remainingPercent: Double) -> UsageSnapshot {
        let fetchedAt = fixtureNow
        return UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "codex",
                name: "Codex",
                window: UsageWindow(
                    remainingPercent: remainingPercent,
                    resetsAt: fetchedAt.addingTimeInterval(4 * 86_400),
                    durationMinutes: 7 * 24 * 60
                )
            ),
            otherLimits: [],
            tokenHistory: [],
            resetCredits: [],
            fetchedAt: fetchedAt
        )
    }

    private nonisolated static let fixtureNow = Date(timeIntervalSince1970: 1_900_000)
}

private struct UsageMonitorTestContext {
    let monitor: UsageMonitor
    let defaults: UserDefaults
    let suiteName: String
    let historyDirectory: URL

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: historyDirectory)
    }
}

private actor SnapshotSequence {
    enum Outcome: Sendable {
        case snapshot(UsageSnapshot)
        case clientError(CodexClientError)
        case genericError
    }

    private var outcomes: [Outcome]
    private var storedFetchCount = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var fetchCount: Int {
        storedFetchCount
    }

    func fetch() throws -> UsageSnapshot {
        storedFetchCount += 1
        guard !outcomes.isEmpty else {
            throw SnapshotSequenceError.missingOutcome
        }
        switch outcomes.removeFirst() {
        case let .snapshot(snapshot):
            return snapshot
        case let .clientError(error):
            throw error
        case .genericError:
            throw SnapshotSequenceError.genericFailure
        }
    }
}

private enum SnapshotSequenceError: Error, Sendable {
    case genericFailure
    case missingOutcome
}

private actor SuspendedSnapshotSource {
    private var storedFetchCount = 0
    private var resultContinuation: CheckedContinuation<UsageSnapshot, Never>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []

    var fetchCount: Int {
        storedFetchCount
    }

    func fetch() async -> UsageSnapshot {
        storedFetchCount += 1
        let continuations = startedContinuations
        startedContinuations.removeAll()
        continuations.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        guard storedFetchCount == 0 else { return }
        await withCheckedContinuation { continuation in
            startedContinuations.append(continuation)
        }
    }

    func resume(with snapshot: UsageSnapshot) {
        resultContinuation?.resume(returning: snapshot)
        resultContinuation = nil
    }
}
