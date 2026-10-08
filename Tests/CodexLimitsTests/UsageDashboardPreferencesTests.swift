import CodexWidgetKit
import XCTest
@testable import CodexLimits

final class UsageDashboardPreferencesTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testExplicitSelectionSurvivesMainLimitChanging() {
        let snapshot = snapshot(main: .weekly)
        XCTAssertEqual(UsageDashboardPreferences.selectedPeriod(savedValue: UsagePeriod.fiveHour.rawValue,
                                                               snapshot: snapshot, provider: .claude), .fiveHour)
        XCTAssertEqual(UsageDashboardPreferences.selectedPeriod(savedValue: "", snapshot: snapshot, provider: .claude), .weekly)
    }

    func testMissingSelectedPeriodFallsBackWithoutUsingModelLimit() {
        let weekly = reading(.weekly)
        let model = LimitReading(limitId: "claude-sonnet", name: "Sonnet", window: reading(.fiveHour).window)
        let snapshot = UsageSnapshot(mainLimit: weekly, otherLimits: [model], tokenHistory: [], resetCredits: [], fetchedAt: now)

        XCTAssertEqual(UsageDashboardPreferences.selectedPeriod(savedValue: UsagePeriod.fiveHour.rawValue,
                                                               snapshot: snapshot, provider: .claude), .weekly)
        XCTAssertEqual(UsageDashboardPreferences.otherLimits(in: snapshot, provider: .claude), [model])
        let modelOnly = UsageSnapshot(mainLimit: model, otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: now)
        XCTAssertNil(UsageDashboardPreferences.selectedPeriod(savedValue: "", snapshot: modelOnly, provider: .claude))
    }

    func testAccountPeriodsAreRemovedFromOtherLimitsEvenWhenMainLimitIsAModel() {
        let model = LimitReading(limitId: "claude-opus", name: "Opus", window: reading(.weekly).window)
        let snapshot = UsageSnapshot(mainLimit: model, otherLimits: [reading(.fiveHour), reading(.weekly)],
                                     tokenHistory: [], resetCredits: [], fetchedAt: now)
        XCTAssertEqual(UsageDashboardPreferences.otherLimits(in: snapshot, provider: .claude), [model])
    }

    func testPreferenceKeysSeparateBothProvidersAndBothPeriods() throws {
        let keys = UsageProvider.allCases.flatMap { provider in
            provider.periods.flatMap { period in
                ["chartRange", "burndownTarget", UsageMonitor.paceTargetCreditIDKey].map {
                    UsageDashboardPreferences.key($0, provider: provider, period: period)
                }
            }
        }
        XCTAssertEqual(Set(keys).count, 15)
        XCTAssertNotEqual(UsageDashboardPreferences.selectionKey(for: .codex), UsageDashboardPreferences.selectionKey(for: .claude))
        try withDefaults { defaults in
            let fiveHour = UsageDashboardPreferences.key("chartRange", provider: .claude, period: .fiveHour)
            let weekly = UsageDashboardPreferences.key("chartRange", provider: .claude, period: .weekly)
            defaults.set(ChartRange.month.rawValue, forKey: fiveHour)
            defaults.set(ChartRange.week.rawValue, forKey: weekly)
            defaults.set(UsagePeriod.fiveHour.rawValue, forKey: UsageDashboardPreferences.selectionKey(for: .claude))
            defaults.set(UsagePeriod.weekly.rawValue, forKey: UsageDashboardPreferences.selectionKey(for: .claude))
            XCTAssertEqual(defaults.string(forKey: fiveHour), ChartRange.month.rawValue)
            XCTAssertEqual(defaults.string(forKey: weekly), ChartRange.week.rawValue)
        }
    }

    func testMigrationCopiesChartOnlyToOriginalMainPeriodAndCreditsOnlyToWeekly() throws {
        try withDefaults { defaults in
            defaults.set(ChartRange.month.rawValue, forKey: "claude.chartRange")
            defaults.set("credit", forKey: "claude.paceTargetCreditID")
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: snapshot(main: .fiveHour), provider: .claude,
                                                              defaults: defaults, now: now)
            XCTAssertEqual(defaults.string(forKey: key("chartRange", .fiveHour)), ChartRange.month.rawValue)
            XCTAssertNil(defaults.object(forKey: key("chartRange", .weekly)))
            XCTAssertEqual(defaults.string(forKey: key("paceTargetCreditID", .weekly)), "credit")
            XCTAssertNil(defaults.object(forKey: key("paceTargetCreditID", .fiveHour)))
            XCTAssertNil(defaults.object(forKey: "periodPreferencesMigrated"))
        }
    }

    func testMigrationPreservesExistingPeriodChoicesAndDoesNotReapplyLegacyValues() throws {
        try withDefaults { defaults in
            defaults.set(ChartRange.month.rawValue, forKey: "claude.chartRange")
            defaults.set(ChartRange.week.rawValue, forKey: key("chartRange", .weekly))
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: snapshot(), provider: .claude, defaults: defaults, now: now)
            XCTAssertEqual(defaults.string(forKey: key("chartRange", .weekly)), ChartRange.week.rawValue)
            defaults.removeObject(forKey: key("chartRange", .weekly))
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: snapshot(), provider: .claude, defaults: defaults, now: now)
            XCTAssertNil(defaults.object(forKey: key("chartRange", .weekly)))
        }
    }

    func testLegacyTargetMigratesOnlyToItsMatchingPeriod() throws {
        try withDefaults { defaults in
            let weekly = reading(.weekly).window
            let date = now.addingTimeInterval(86_400)
            let legacy = try JSONSerialization.data(withJSONObject: [
                "date": date.timeIntervalSinceReferenceDate,
                "windowReset": weekly.resetsAt.timeIntervalSinceReferenceDate
            ])
            defaults.set(legacy, forKey: "claude.burndownTarget")
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: snapshot(), provider: .claude, defaults: defaults, now: now)
            let data = try XCTUnwrap(defaults.data(forKey: key("burndownTarget", .weekly)))
            let restored = try JSONDecoder().decode(BurndownTarget.self, from: data)
            XCTAssertEqual(restored.date, date)
            XCTAssertTrue(restored.isValid(in: weekly, now: now))
            XCTAssertNil(defaults.data(forKey: key("burndownTarget", .fiveHour)))
        }
    }

    func testAmbiguousLegacyTargetIsNotCopiedToEitherPeriod() throws {
        try withDefaults { defaults in
            let reset = now.addingTimeInterval(3_600)
            let sharedResetSnapshot = snapshot(sharedReset: reset)
            let legacy = try JSONSerialization.data(withJSONObject: [
                "date": now.addingTimeInterval(1_800).timeIntervalSinceReferenceDate,
                "windowReset": reset.timeIntervalSinceReferenceDate
            ])
            defaults.set(legacy, forKey: "claude.burndownTarget")
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: sharedResetSnapshot, provider: .claude,
                                                              defaults: defaults, now: now)
            XCTAssertNil(defaults.data(forKey: key("burndownTarget", .weekly)))
            XCTAssertNil(defaults.data(forKey: key("burndownTarget", .fiveHour)))
            XCTAssertEqual(defaults.data(forKey: "claude.burndownTarget"), legacy)
        }
    }

    func testDurationIdentifiesTargetWhenPeriodsShareReset() throws {
        try withDefaults { defaults in
            let reset = now.addingTimeInterval(3_600)
            let sharedResetSnapshot = snapshot(sharedReset: reset)
            let target = try XCTUnwrap(BurndownTarget(date: now.addingTimeInterval(1_800),
                                                    window: reading(.fiveHour, reset: reset).window, now: now))
            defaults.set(try JSONEncoder().encode(target), forKey: "claude.burndownTarget")
            UsageDashboardPreferences.migrateLegacyPreferences(snapshot: sharedResetSnapshot, provider: .claude,
                                                              defaults: defaults, now: now)
            XCTAssertNotNil(defaults.data(forKey: key("burndownTarget", .fiveHour)))
            XCTAssertNil(defaults.data(forKey: key("burndownTarget", .weekly)))
        }
    }

    private func reading(_ period: UsagePeriod, reset: Date? = nil) -> LimitReading {
        LimitReading(limitId: "claude", name: period.title,
                     window: UsageWindow(remainingPercent: 70,
                                         resetsAt: reset ?? now.addingTimeInterval(period == .weekly ? 3 * 86_400 : 3_600),
                                         durationMinutes: period.durationMinutes))
    }

    private func snapshot(main: UsagePeriod = .weekly, sharedReset: Date? = nil) -> UsageSnapshot {
        UsageSnapshot(mainLimit: reading(main, reset: sharedReset),
                      otherLimits: [reading(main == .weekly ? .fiveHour : .weekly, reset: sharedReset)],
                      tokenHistory: [], resetCredits: [], fetchedAt: now)
    }

    private func key(_ name: String, _ period: UsagePeriod) -> String {
        UsageDashboardPreferences.key(name, provider: .claude, period: period)
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "UsageDashboardPreferencesTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }
}
