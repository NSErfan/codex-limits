import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

final class WeeklyWidgetPublisherTests: XCTestCase {
    private let now = Date()

    func testWeeklySelectionIgnoresMoreConstrainedShortWindowAndModelLimits() {
        let usage = snapshot()
        let value = WeeklyWidgetPublisher.snapshot(from: usage)
        XCTAssertEqual(value.window?.remainingPercent, 68)
        XCTAssertEqual(value.samples.count, 1)
        XCTAssertEqual(value.samples.first?.remainingPercent, 68)
    }

    func testNoWeeklyLimitProducesUnavailableState() {
        let usage = snapshot(includeWeekly: false)
        let value = WeeklyWidgetPublisher.snapshot(from: usage)
        XCTAssertNil(value.window)
        XCTAssertNil(value.pace)
        XCTAssertEqual(value.status(at: now), .unavailable)
    }

    func testWeeklyPaceUsesForecastRulesAndSafetyBuffer() {
        for (remaining, expected) in [(20.0, WeeklyPace.slowDown), (59, .onTrack), (80, .roomToUseMore)] {
            let weekly = UsageWindow(remainingPercent: remaining, resetsAt: now.addingTimeInterval(4 * 86_400), durationMinutes: 10_080)
            let usage = UsageSnapshot(mainLimit: .init(limitId: "codex", name: "Weekly", window: weekly),
                                      otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: now)
            XCTAssertEqual(WeeklyWidgetPublisher.snapshot(from: usage).pace, expected)
            if remaining == 59 {
                XCTAssertEqual(WeeklyWidgetPublisher.snapshot(from: usage, safetyBuffer: 20).pace, .slowDown)
            }
        }
    }

    @MainActor
    func testMonitorPublishesWeeklyReadingAfterSuccessfulRefreshAndPreservesItOnFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WeeklyWidgetPublisherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = WeeklyWidgetStore(directory: folder.appendingPathComponent("widget"))
        let usage = snapshot()
        let monitor = UsageMonitor(
            defaults: defaults, historyDirectory: folder.appendingPathComponent("history"),
            widgetStore: store, fetchUsage: { usage }, startsAutomatically: false
        )
        await monitor.refresh()
        XCTAssertEqual(store.read()?.window?.remainingPercent, 68)
        let failing = UsageMonitor(
            defaults: defaults, historyDirectory: folder.appendingPathComponent("history"),
            widgetStore: store, fetchUsage: { throw CodexClientError.invalidResponse },
            recoveryDelaysNanoseconds: [], startsAutomatically: false
        )
        await failing.refresh()
        XCTAssertEqual(store.read()?.fetchedAt, usage.fetchedAt)
        XCTAssertEqual(store.read()?.window?.remainingPercent, 68)
    }

    func testBackgroundCollectorPublishesWeeklyLimitEvenWhenMainLimitIsShort() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "WeeklyWidgetPublisherTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
        let store = WeeklyWidgetStore(directory: folder.appendingPathComponent("widget"))
        let usage = snapshot()
        let success = await BackgroundCollector.collectOnce(
            defaults: defaults, historyDirectory: folder.appendingPathComponent("history"),
            widgetStore: store, fetchUsage: { usage }
        )
        XCTAssertTrue(success)
        XCTAssertEqual(store.read()?.window?.remainingPercent, 68)
    }

    private func snapshot(includeWeekly: Bool = true) -> UsageSnapshot {
        let weekly = UsageWindow(remainingPercent: 68, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080)
        return UsageSnapshot(
            mainLimit: .init(limitId: "codex", name: "Codex", window: .init(remainingPercent: 2, resetsAt: weekly.resetsAt, durationMinutes: 300)),
            otherLimits: [.init(limitId: "model", name: "Model", window: weekly)] + (includeWeekly ? [.init(limitId: "codex", name: "Weekly", window: weekly)] : []),
            tokenHistory: [], resetCredits: [], fetchedAt: now
        )
    }
}
