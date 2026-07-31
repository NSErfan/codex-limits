import Foundation

/// Moves preferences and usage history from the pre-fork bundle identifier.
///
/// The app was renamed from `com.github.thrr87.CodexLimits` when this fork became
/// independent. macOS keys both `UserDefaults` and the Application Support
/// directory by bundle identifier, so without this the rename would orphan every
/// saved preference and the whole recorded usage history.
enum LegacyBundleMigration {
    static let legacyIdentifier = "com.github.thrr87.CodexLimits"
    static let completionKey = "migratedFromLegacyBundle"

    private static let migratedKeys = [
        UsageMonitor.safetyBufferKey,
        UsageMonitor.paceTargetCreditIDKey,
        "usageState",
        "historyInstallationID",
        "historySyncBookmark",
        "chartRange",
        LoginItem.preferenceKey
    ]

    /// Runs once. Later launches, and installs that never saw the old bundle, do nothing.
    static func run(
        identifier: String = Bundle.main.bundleIdentifier ?? "",
        defaults: UserDefaults = .standard,
        legacyDefaults: UserDefaults? = UserDefaults(suiteName: legacyIdentifier),
        applicationSupport: URL? = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first
    ) {
        guard identifier != legacyIdentifier,
              !defaults.bool(forKey: completionKey) else { return }

        if let applicationSupport {
            migrateSupportDirectory(
                from: applicationSupport.appendingPathComponent(legacyIdentifier, isDirectory: true),
                to: applicationSupport.appendingPathComponent(identifier, isDirectory: true)
            )
        }
        if let legacyDefaults {
            migratePreferences(from: legacyDefaults, to: defaults)
        }
        defaults.set(true, forKey: completionKey)
    }

    /// Copies rather than moves, so an older build of the app keeps working and a
    /// failed migration can never destroy the only copy of the history.
    private static func migrateSupportDirectory(from legacy: URL, to destination: URL) {
        let manager = FileManager.default
        guard manager.fileExists(atPath: legacy.path),
              !manager.fileExists(atPath: destination.path) else { return }
        try? manager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? manager.copyItem(at: legacy, to: destination)
    }

    /// Values already set under the new identifier win, so a partly configured
    /// new install is never overwritten by stale values.
    private static func migratePreferences(from legacy: UserDefaults, to defaults: UserDefaults) {
        for key in migratedKeys {
            guard defaults.object(forKey: key) == nil,
                  let value = legacy.object(forKey: key) else { continue }
            defaults.set(value, forKey: key)
        }
    }
}
