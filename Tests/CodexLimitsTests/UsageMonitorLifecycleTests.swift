import AppKit
import CodexWidgetKit
import XCTest
@testable import CodexLimits

/// start() and stop() back the provider on/off setting: a stopped monitor must never fetch again.
@MainActor
final class UsageMonitorLifecycleTests: XCTestCase {
    func testStopCancelsPendingRecovery() async throws {
        let source = GatedSource(outcomes: [.failure, .success(Self.snapshot(remainingPercent: 60))])
        let context = try Context(source: source, recoveryDelaysNanoseconds: [50_000_000])
        defer { context.cleanUp() }

        await context.monitor.refresh()
        context.monitor.stop()
        try await Task.sleep(for: .milliseconds(150))

        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertNil(context.monitor.snapshot)
    }

    func testRefreshFinishingAfterStopDoesNotScheduleRecovery() async throws {
        let source = GatedSource(outcomes: [.failure, .success(Self.snapshot(remainingPercent: 60))], gatesFirstFetch: true)
        let context = try Context(source: source, recoveryDelaysNanoseconds: [0])
        defer { context.cleanUp() }

        let refresh = Task { await context.monitor.refresh() }
        await source.waitForFetchCount(1)
        context.monitor.stop()
        await source.openGate()
        _ = await refresh.value
        try await Task.sleep(for: .milliseconds(50))

        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1)
    }

    func testStoppedMonitorRefusesRefreshUntilStartedAgain() async throws {
        let snapshot = Self.snapshot(remainingPercent: 71)
        let source = GatedSource(outcomes: [.success(snapshot)])
        let context = try Context(source: source)
        defer { context.cleanUp() }

        context.monitor.stop()
        let refusedRefresh = await context.monitor.refresh()

        XCTAssertFalse(refusedRefresh)
        var fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 0)

        await context.monitor.start()
        defer { context.monitor.stop() }

        fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(context.monitor.snapshot, snapshot)
    }

    func testWakeRefreshesOnlyWhileRunningAndStartingTwiceSubscribesOnce() async throws {
        let source = GatedSource(outcomes: (0 ..< 4).map { .success(Self.snapshot(remainingPercent: 80 - Double($0))) })
        let context = try Context(source: source)
        defer { context.cleanUp() }

        await context.monitor.start()
        await context.monitor.start()
        var fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1, "A second start() must not refresh or subscribe again")

        Self.postWake()
        await source.waitForFetchCount(2)
        try await Task.sleep(for: .milliseconds(100))
        fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 2, "One wake should cause exactly one refresh")

        context.monitor.stop()
        Self.postWake()
        try await Task.sleep(for: .milliseconds(100))
        fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testStopDuringStartKeepsMonitorStopped() async throws {
        let source = GatedSource(outcomes: [.success(Self.snapshot(remainingPercent: 55)), .success(Self.snapshot(remainingPercent: 54))],
                                 gatesFirstFetch: true)
        let context = try Context(source: source)
        defer { context.cleanUp() }

        let start = Task { await context.monitor.start() }
        await source.waitForFetchCount(1)
        context.monitor.stop()
        await source.openGate()
        await start.value

        Self.postWake()
        try await Task.sleep(for: .milliseconds(100))
        let refused = await context.monitor.refresh()

        XCTAssertFalse(refused)
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1)
        XCTAssertEqual(context.monitor.snapshot?.mainLimit.window.remainingPercent, 55,
                       "A fetch already in progress still saves its reading")
    }

    private static func postWake() {
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: NSWorkspace.shared)
    }

    private static func snapshot(remainingPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(limitId: "codex", name: "Codex", window: UsageWindow(
                remainingPercent: remainingPercent, resetsAt: fixtureNow.addingTimeInterval(4 * 86_400),
                durationMinutes: 10_080)),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: fixtureNow
        )
    }

    private nonisolated static let fixtureNow = Date(timeIntervalSince1970: 1_900_000)

    @MainActor
    private struct Context {
        let monitor: UsageMonitor
        let defaults: UserDefaults
        let suiteName = "UsageMonitorLifecycleTests.\(UUID().uuidString)"
        let directory: URL

        init(source: GatedSource, recoveryDelaysNanoseconds: [UInt64] = []) throws {
            defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(suiteName, isDirectory: true)
            let historyNow = UsageMonitorLifecycleTests.fixtureNow
            monitor = UsageMonitor(
                defaults: defaults,
                historyDirectory: directory,
                historyNow: { historyNow },
                widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("widget")),
                fetchUsage: { try await source.fetch() },
                recoveryDelaysNanoseconds: recoveryDelaysNanoseconds,
                startsAutomatically: false
            )
        }

        func cleanUp() {
            monitor.stop()
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }
}

/// Returns queued outcomes in order; optionally holds the first fetch until openGate().
private actor GatedSource {
    enum Outcome: Sendable {
        case success(UsageSnapshot)
        case failure
    }

    private var outcomes: [Outcome]
    private var gateIsClosed: Bool
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var fetchCount = 0

    init(outcomes: [Outcome], gatesFirstFetch: Bool = false) {
        self.outcomes = outcomes
        gateIsClosed = gatesFirstFetch
    }

    func fetch() async throws -> UsageSnapshot {
        fetchCount += 1
        let ready = countWaiters.filter { fetchCount >= $0.0 }
        countWaiters.removeAll { fetchCount >= $0.0 }
        ready.forEach { $0.1.resume() }
        if gateIsClosed {
            await withCheckedContinuation { gateWaiters.append($0) }
        }
        guard !outcomes.isEmpty else { throw CodexClientError.invalidResponse }
        switch outcomes.removeFirst() {
        case let .success(snapshot): return snapshot
        case .failure: throw CodexClientError.invalidResponse
        }
    }

    func openGate() {
        gateIsClosed = false
        gateWaiters.forEach { $0.resume() }
        gateWaiters.removeAll()
    }

    func waitForFetchCount(_ count: Int) async {
        guard fetchCount < count else { return }
        await withCheckedContinuation { countWaiters.append((count, $0)) }
    }
}
