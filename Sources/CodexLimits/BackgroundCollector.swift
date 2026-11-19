import Foundation
import CodexWidgetKit

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
        return await collectEnabledAccounts(defaults: .standard) { account in
            await collectOnce(
                defaults: .standard,
                historyDirectory: UsageMonitor.historyDirectory(account: account),
                account: account,
                fetchUsage: {
                    switch try await scheduledFetch(provider: account.provider, fetch: { try await account.fetchUsage() }) {
                    case let .fetched(snapshot, _), let .cached(snapshot, _): snapshot
                    case let .deferred(error, _, _): throw error
                    }
                }
            )
        }
    }

    /// Collects each enabled account, in turn; true when any collection succeeded.
    static func collectEnabledAccounts(
        defaults: UserDefaults,
        collect: (UsageAccount) async -> Bool
    ) async -> Bool {
        var collectedAny = false
        let accounts = UsageAccount.enabledAccounts(
            providers: ProviderEnablement.enabledProviders(in: defaults),
            secondCodexEnabled: defaults.bool(forKey: UsageAccount.secondCodexEnabledKey)
        )
        for account in accounts {
            let collected = await collect(account)
            collectedAny = collectedAny || collected
        }
        return collectedAny
    }

    static func scheduledFetch(
        provider: UsageProvider,
        now: @Sendable () -> Date = { Date() },
        sleep: @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        fetch: @Sendable () async throws -> UsageFetchResult
    ) async throws -> UsageFetchResult {
        let result = try await fetch()
        guard provider.refreshSchedule == .fetchDeadline, let next = result.nextRefreshAt else { return result }
        let delay = next.timeIntervalSince(now())
        // launchd's fixed cadence can arrive just before the prior check's deadline.
        // Wait outside the lock, then recheck once so the collector doesn't skip a whole period.
        guard delay > 0, delay <= 60 else { return result }
        try await sleep(delay)
        return try await fetch()
    }

    static func collectOnce(
        defaults: UserDefaults,
        historyDirectory: URL,
        widgetStore: WeeklyWidgetStore? = nil,
        account: UsageAccount = .primaryCodex,
        fetchUsage: @Sendable () async throws -> UsageSnapshot
    ) async -> Bool {
        guard let snapshot = try? await fetchUsage(),
              let location = account.historyLocation(at: historyDirectory, subscription: snapshot.subscriptionKey)
        else { return false }
        let provider = account.provider
        let window = snapshot.mainLimit.window
        let sample = UsageSample(
            observedAt: snapshot.fetchedAt,
            remainingPercent: window.remainingPercent,
            resetsAt: window.resetsAt,
            durationMinutes: window.durationMinutes
        )
        let history = UsageHistory(
            localDirectory: location.directory,
            installationID: installationID(in: defaults)
        )
        let recorded = await history.record(sample)
        let periodHistory = UsagePeriodHistory(
            localDirectory: location.directory,
            installationID: installationID(in: defaults),
            provider: provider
        )
        let periods = await periodHistory.record(snapshot)
        if account.publishesWeeklyWidget {
            let store = widgetStore ?? .shared(provider: provider) ?? WeeklyWidgetStore(
                directory: historyDirectory.appendingPathComponent("WeeklyWidget", isDirectory: true),
                provider: provider
            )
            WeeklyWidgetPublisher.publish(snapshot, writer: .collector, store: store,
                                          safetyBuffer: defaults.object(forKey: UsageMonitor.safetyBufferKey) as? Double ?? 3,
                                          provider: provider)
        }
        return recorded.errorMessage == nil && periods.errorMessage == nil
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
