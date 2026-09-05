import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class AppearanceSettingsTests: XCTestCase {
    func testSelectionPersistsAcrossRelaunchAndSharesWithWidgets() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = WeeklyWidgetStore(directory: directory)
        let settings = AppearanceSettings(defaults: defaults, widgetStore: store, reloadWidgets: {})
        XCTAssertEqual(settings.accent, .automatic)
        let custom = UsageAccent.custom(red: 0.15, green: 0.42, blue: 0.9)
        settings.setAccent(custom)

        let relaunched = AppearanceSettings(defaults: defaults, widgetStore: store, reloadWidgets: {})
        XCTAssertEqual(relaunched.accent, custom)
        XCTAssertEqual(store.readAccent(), custom)
        XCTAssertNil(relaunched.widgetError)

        relaunched.setAccent(.automatic)
        XCTAssertEqual(store.readAccent(), .automatic)
        XCTAssertEqual(AppearanceSettings(defaults: defaults, widgetStore: nil).accent, .automatic)
    }

    func testRelaunchRepairsSharedAppearanceAndRejectsInvalidCustomColor() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = WeeklyWidgetStore(directory: directory)
        defaults.set(try JSONEncoder().encode(UsageAccent.violet), forKey: AppearanceSettings.preferenceKey)
        try store.writeAccent(.blue)
        let settings = AppearanceSettings(defaults: defaults, widgetStore: store, reloadWidgets: {})
        XCTAssertEqual(settings.accent, .violet)
        XCTAssertEqual(store.readAccent(), .violet)
        settings.setAccent(.custom(red: .nan, green: 0, blue: 0))
        XCTAssertEqual(settings.accent, .violet)
        XCTAssertEqual(store.readAccent(), .violet)
    }

    func testFailedSharingKeepsLocalSelectionAndReportsRetry() throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        // A regular file cannot be used as the shared directory.
        try Data().write(to: directory)
        let settings = AppearanceSettings(
            defaults: defaults, widgetStore: WeeklyWidgetStore(directory: directory), reloadWidgets: {}
        )
        settings.setAccent(.rose)
        XCTAssertEqual(settings.accent, .rose)
        XCTAssertNotNil(settings.widgetError)
        XCTAssertEqual(AppearanceSettings(defaults: defaults, widgetStore: nil).accent, .rose)

        try FileManager.default.removeItem(at: directory)
        settings.setAccent(.rose)
        XCTAssertNil(settings.widgetError)
        XCTAssertEqual(WeeklyWidgetStore(directory: directory).readAccent(), .rose)
    }

    func testRapidChangesRequestOnlyOneWidgetReload() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var reloads = 0
        let store = WeeklyWidgetStore(directory: directory)
        let settings = AppearanceSettings(defaults: defaults, widgetStore: store, reloadWidgets: { reloads += 1 })
        settings.setAccent(.mint)
        settings.setAccent(.blue)
        settings.setAccent(.orange)
        XCTAssertEqual(store.readAccent(), .orange)
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(reloads, 1)
    }
}
