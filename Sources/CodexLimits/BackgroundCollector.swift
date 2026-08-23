import Foundation

/// Headless mode run by the bundled LaunchAgent: records one usage sample into
/// the shared history store and exits, so the charts keep their shape over
/// periods when the menu bar app is closed.
enum BackgroundCollector {
    static let argument = "--collect"
    static let installationIDKey = "collectorHistoryInstallationID"

    static func shouldRun(arguments: [String]) -> Bool {
        arguments.dropFirst().contains(argument)
    }

    static func runBlocking() -> Int32 {
        let outcome = OutcomeBox()
        let finished = DispatchSemaphore(value: 0)
        Task.detached {
            outcome.set(await collectOnce())
            finished.signal()
        }
        finished.wait()
        return outcome.get() ? 0 : 1
    }

    private static func collectOnce() async -> Bool {
        // Must precede any preference or history access.
        LegacyBundleMigration.run()
        return await collectOnce(
            defaults: .standard,
            historyDirectory: UsageMonitor.historyDirectory(),
            fetchUsage: { try await CodexClient.fetch() }
        )
    }

    static func collectOnce(
        defaults: UserDefaults,
        historyDirectory: URL,
        fetchUsage: @Sendable () async throws -> UsageSnapshot
    ) async -> Bool {
        guard let snapshot = try? await fetchUsage() else { return false }
        let window = snapshot.mainLimit.window
        let sample = UsageSample(
            observedAt: snapshot.fetchedAt,
            remainingPercent: window.remainingPercent,
            resetsAt: window.resetsAt
        )
        let history = UsageHistory(
            localDirectory: historyDirectory,
            installationID: installationID(in: defaults)
        )
        return await history.record(sample).errorMessage == nil
    }

    /// The collector writes under its own history installation so its files
    /// never race the app's uncoordinated writes to the same day file.
    static func installationID(in defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: installationIDKey),
           let uuid = UUID(uuidString: existing) {
            return uuid.uuidString.lowercased()
        }
        let created = UUID().uuidString.lowercased()
        defaults.set(created, forKey: installationIDKey)
        return created
    }

    private final class OutcomeBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = false

        func set(_ value: Bool) {
            lock.lock()
            stored = value
            lock.unlock()
        }

        func get() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }
}
