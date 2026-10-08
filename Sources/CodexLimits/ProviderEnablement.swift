import CodexWidgetKit
import Foundation

/// Which providers the user has turned on. The app and the background
/// collector share this through the app's preferences.
enum ProviderEnablement {
    /// Turned-off providers are stored, rather than turned-on ones, so newly added providers start on.
    static let disabledKey = "disabledUsageProviders"

    /// Turned-on providers in declaration order. At least one provider is always on.
    static func enabledProviders(in defaults: UserDefaults) -> [UsageProvider] {
        let disabled = Set(storedDisabledValues(in: defaults))
        let enabled = UsageProvider.allCases.filter { !disabled.contains($0.rawValue) }
        return enabled.isEmpty ? UsageProvider.allCases : enabled
    }

    /// Returns whether the providers that are on changed. The last provider that is on can't be turned off.
    @discardableResult
    static func setEnabled(_ enabled: Bool, for provider: UsageProvider, in defaults: UserDefaults) -> Bool {
        let current = enabledProviders(in: defaults)
        guard current.contains(provider) != enabled else { return false }
        guard enabled || current.count > 1 else { return false }
        // Rebuild from what is shown, so a stored state that falls back to every provider can't
        // cancel the change. Keep values this version doesn't recognize, so a newer version's
        // choices survive a downgrade.
        let unrecognized = storedDisabledValues(in: defaults).filter { UsageProvider(rawValue: $0) == nil }
        var disabled = UsageProvider.allCases.filter { !current.contains($0) && $0 != provider }
        if !enabled { disabled.append(provider) }
        defaults.set(unrecognized + disabled.map(\.rawValue), forKey: disabledKey)
        return true
    }

    private static func storedDisabledValues(in defaults: UserDefaults) -> [String] {
        defaults.stringArray(forKey: disabledKey) ?? []
    }
}
