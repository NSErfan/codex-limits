import CodexWidgetKit
import XCTest
@testable import CodexLimits

@MainActor
final class MenuContentViewTests: XCTestCase {
    func testWeeklyOnlyAccountDoesNotShowFiveHourSelector() async throws {
        for provider in [UsageProvider.codex, .claude] {
            let showsPicker = try await showsPeriodPicker(provider: provider, reportsFiveHour: false)

            XCTAssertFalse(showsPicker, "\(provider) must not offer an account window it does not report")
        }
    }

    func testReportedFiveHourWindowShowsBothWindowControls() async throws {
        for provider in [UsageProvider.codex, .claude] {
            let showsPicker = try await showsPeriodPicker(provider: provider, reportsFiveHour: true)

            XCTAssertTrue(showsPicker, "\(provider) must offer a reported five-hour window even when weekly is primary")
        }
    }

    private func showsPeriodPicker(provider: UsageProvider, reportsFiveHour: Bool) async throws -> Bool {
        let suite = "MenuContentViewTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let now = Date()
        let weekly = LimitReading(limitId: provider.rawValue, name: "Weekly", window: UsageWindow(
            remainingPercent: 84, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 10_080
        ))
        let fiveHour = LimitReading(
            limitId: reportsFiveHour ? provider.rawValue : "\(provider.rawValue)-model",
            name: "Model allowance",
            window: UsageWindow(remainingPercent: 86, resetsAt: now.addingTimeInterval(3_600), durationMinutes: 300)
        )
        let snapshot = UsageSnapshot(mainLimit: weekly, otherLimits: [fiveHour], tokenHistory: [],
                                     resetCredits: [], fetchedAt: now)
        let monitor = UsageMonitor(
            provider: provider, defaults: defaults, historyDirectory: directory,
            widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("widget"), provider: provider),
            fetchUsage: { snapshot }, startsAutomatically: false
        )
        await monitor.refresh()
        XCTAssertEqual(monitor.snapshot?.limit(for: .weekly, provider: provider)?.window.remainingPercent, 84)
        let view = MenuContentView(
            monitor: monitor, showsFooterActions: false, refreshesOnAppear: false, defaults: defaults
        )
        return view.showsPeriodPicker
    }
}
