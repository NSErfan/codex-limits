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

    func testTransientFailureRecoversAutomatically() async throws {
        let expected = Self.snapshot(remainingPercent: 67)
        let source = SnapshotSequence(
            outcomes: [.clientError(.invalidResponse), .snapshot(expected)]
        )
        let context = try makeContext(recoveryDelaysNanoseconds: [0]) {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        await source.waitForFetchCount(2)
        while context.monitor.isRefreshing {
            await Task.yield()
        }

        XCTAssertEqual(context.monitor.snapshot, expected)
        XCTAssertNil(context.monitor.errorMessage)
        XCTAssertEqual(context.monitor.samples.count, 1)
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testAutomaticRecoveryReplacesCachedSnapshotOnlyAfterSuccess() async throws {
        let cached = Self.snapshot(remainingPercent: 42)
        let recovered = Self.snapshot(remainingPercent: 69)
        let source = SnapshotSequence(
            outcomes: [
                .snapshot(cached),
                .clientError(.invalidResponse),
                .snapshot(recovered)
            ]
        )
        let context = try makeContext(recoveryDelaysNanoseconds: [10_000_000]) {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        await context.monitor.refresh()

        XCTAssertEqual(context.monitor.snapshot, cached)
        XCTAssertEqual(
            context.monitor.errorMessage,
            CodexClientError.invalidResponse.localizedDescription
        )

        await source.waitForFetchCount(3)
        while context.monitor.isRefreshing {
            await Task.yield()
        }

        XCTAssertEqual(context.monitor.snapshot, recovered)
        XCTAssertNil(context.monitor.errorMessage)
        XCTAssertEqual(context.monitor.samples.count, 2)
    }

    func testAutomaticRecoveryStopsAfterConfiguredAttempts() async throws {
        let source = SnapshotSequence(
            outcomes: [
                .clientError(.invalidResponse),
                .clientError(.invalidResponse),
                .clientError(.invalidResponse)
            ]
        )
        let context = try makeContext(recoveryDelaysNanoseconds: [0, 0]) {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        await source.waitForFetchCount(3)
        while context.monitor.isRefreshing {
            await Task.yield()
        }
        for _ in 0 ..< 10 {
            await Task.yield()
        }

        XCTAssertNil(context.monitor.snapshot)
        XCTAssertEqual(
            context.monitor.errorMessage,
            CodexClientError.invalidResponse.localizedDescription
        )
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 3)
    }

    func testAutomaticRecoveryUsesConfiguredBackoffOrder() async throws {
        let expected = Self.snapshot(remainingPercent: 73)
        let source = SnapshotSequence(
            outcomes: [
                .clientError(.invalidResponse),
                .clientError(.timedOut),
                .genericError,
                .snapshot(expected)
            ]
        )
        let delayRecorder = RecoveryDelayRecorder()
        let context = try makeContext(
            recoveryDelaysNanoseconds: [3, 5, 8],
            sleepBeforeRecovery: { await delayRecorder.record($0) }
        ) {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        await source.waitForFetchCount(4)
        while context.monitor.isRefreshing {
            await Task.yield()
        }

        XCTAssertEqual(context.monitor.snapshot, expected)
        let recordedDelays = await delayRecorder.delays
        XCTAssertEqual(recordedDelays, [3, 5, 8])
    }

    func testPermanentClientFailuresDoNotScheduleAutomaticRecovery() async throws {
        for error in [CodexClientError.cliNotFound, .mainLimitMissing] {
            let source = SnapshotSequence(
                outcomes: [.clientError(error), .genericError]
            )
            let context = try makeContext(recoveryDelaysNanoseconds: [0]) {
                try await source.fetch()
            }
            defer { context.cleanUp() }

            await context.monitor.refresh()
            for _ in 0 ..< 10 {
                await Task.yield()
            }

            let fetchCount = await source.fetchCount
            XCTAssertEqual(fetchCount, 1)
            XCTAssertEqual(context.monitor.errorMessage, error.localizedDescription)
        }
    }

    func testManualRefreshCancelsPendingAutomaticRecovery() async throws {
        let expected = Self.snapshot(remainingPercent: 71)
        let source = SnapshotSequence(
            outcomes: [.clientError(.invalidResponse), .snapshot(expected)]
        )
        let context = try makeContext(recoveryDelaysNanoseconds: [50_000_000]) {
            try await source.fetch()
        }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        await context.monitor.refresh()
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(context.monitor.snapshot, expected)
        XCTAssertNil(context.monitor.errorMessage)
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

    func testPaceTargetToggleRecalculatesFromTheExplicitSelection() async throws {
        let fetchedAt = Self.fixtureNow
        let credit = ResetCredit(
            id: "banked-reset",
            title: "Full reset",
            expiresAt: fetchedAt.addingTimeInterval(2 * 86_400)
        )
        let snapshot = UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "codex",
                name: "Codex",
                window: UsageWindow(
                    remainingPercent: 60,
                    resetsAt: fetchedAt.addingTimeInterval(4 * 86_400),
                    durationMinutes: 7 * 24 * 60
                )
            ),
            otherLimits: [],
            tokenHistory: [],
            resetCredits: [credit],
            fetchedAt: fetchedAt
        )
        let source = SnapshotSequence(outcomes: [.snapshot(snapshot)])
        let context = try makeContext { try await source.fetch() }
        defer { context.cleanUp() }

        await context.monitor.refresh()
        let weeklyPace = try XCTUnwrap(context.monitor.forecast?.recommendedPercentPerDay)

        context.monitor.updatePaceTarget(credit.id)
        let bankedPace = try XCTUnwrap(context.monitor.forecast?.recommendedPercentPerDay)

        XCTAssertEqual(
            context.defaults.string(forKey: UsageMonitor.paceTargetCreditIDKey),
            credit.id
        )
        XCTAssertGreaterThan(bankedPace, weeklyPace)

        context.monitor.updatePaceTarget("")

        XCTAssertEqual(context.monitor.forecast?.recommendedPercentPerDay, weeklyPace)
    }

    private func makeContext(
        recoveryDelaysNanoseconds: [UInt64] = [],
        sleepBeforeRecovery: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        },
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
            recoveryDelaysNanoseconds: recoveryDelaysNanoseconds,
            sleepBeforeRecovery: sleepBeforeRecovery,
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
    private var fetchCountWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var fetchCount: Int {
        storedFetchCount
    }

    func fetch() throws -> UsageSnapshot {
        storedFetchCount += 1
        let readyWaiters = fetchCountWaiters.filter { storedFetchCount >= $0.0 }
        fetchCountWaiters.removeAll { storedFetchCount >= $0.0 }
        readyWaiters.forEach { $0.1.resume() }
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

    func waitForFetchCount(_ expectedCount: Int) async {
        guard storedFetchCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            fetchCountWaiters.append((expectedCount, continuation))
        }
    }
}

private enum SnapshotSequenceError: Error, Sendable {
    case genericFailure
    case missingOutcome
}

private actor RecoveryDelayRecorder {
    private(set) var delays: [UInt64] = []

    func record(_ delay: UInt64) {
        delays.append(delay)
    }
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
