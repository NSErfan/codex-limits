import CodexWidgetKit
import Foundation

enum UsageDashboardPreferences {
    static func selectionKey(for provider: UsageProvider) -> String {
        provider.preferenceKey("usagePeriod")
    }

    static func key(_ name: String, provider: UsageProvider, period: UsagePeriod) -> String {
        provider.preferenceKey("period.\(period.rawValue).\(name)")
    }

    static func selectedPeriod(savedValue: String, snapshot: UsageSnapshot, provider: UsageProvider) -> UsagePeriod? {
        let available = UsagePeriod.allCases.filter { snapshot.limit(for: $0, provider: provider) != nil }
        if let selected = UsagePeriod(rawValue: savedValue), available.contains(selected) { return selected }
        return available.first { $0.durationMinutes == snapshot.mainLimit.window.durationMinutes } ?? available.first
    }

    static func otherLimits(in snapshot: UsageSnapshot, provider: UsageProvider) -> [LimitReading] {
        let accountIDs = Set(UsagePeriod.allCases.compactMap { snapshot.limit(for: $0, provider: provider)?.id })
        return ([snapshot.mainLimit] + snapshot.otherLimits).filter { !accountIDs.contains($0.id) }
    }

    static func migrateLegacyPreferences(
        snapshot: UsageSnapshot,
        provider: UsageProvider,
        defaults: UserDefaults = .standard,
        now: Date = .now
    ) {
        let migrationKey = provider.preferenceKey("periodPreferencesMigrated")
        guard !defaults.bool(forKey: migrationKey),
              let initialPeriod = selectedPeriod(savedValue: "", snapshot: snapshot, provider: provider) else { return }

        migrateValue("chartRange", to: initialPeriod, provider: provider, defaults: defaults)
        migrateValue(UsageMonitor.paceTargetCreditIDKey, to: .weekly, provider: provider, defaults: defaults)
        migrateLegacyTarget(snapshot: snapshot, provider: provider, defaults: defaults, now: now)
        defaults.set(true, forKey: migrationKey)
    }

    private static func migrateValue(_ name: String, to period: UsagePeriod, provider: UsageProvider, defaults: UserDefaults) {
        let destination = key(name, provider: provider, period: period)
        guard defaults.object(forKey: destination) == nil,
              let existing = defaults.object(forKey: provider.preferenceKey(name)) else { return }
        defaults.set(existing, forKey: destination)
    }

    private static func migrateLegacyTarget(snapshot: UsageSnapshot, provider: UsageProvider, defaults: UserDefaults, now: Date) {
        guard let data = defaults.data(forKey: provider.preferenceKey("burndownTarget")),
              let target = try? JSONDecoder().decode(BurndownTarget.self, from: data) else { return }
        let matches = UsagePeriod.allCases.filter {
            guard let window = snapshot.limit(for: $0, provider: provider)?.window else { return false }
            return target.isValid(in: window, now: now)
        }
        // Older targets lack duration. A shared reset cannot identify the intended period.
        guard matches.count == 1, let period = matches.first,
              let window = snapshot.limit(for: period, provider: provider)?.window,
              let migrated = BurndownTarget(date: target.date, window: window, now: now),
              let migratedData = try? JSONEncoder().encode(migrated) else { return }
        let destination = key("burndownTarget", provider: provider, period: period)
        guard defaults.object(forKey: destination) == nil else { return }
        defaults.set(migratedData, forKey: destination)
    }
}
