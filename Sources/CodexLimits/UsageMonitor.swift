import AppKit
import Combine
import CodexWidgetKit
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    nonisolated static let safetyBufferKey = "safetyBuffer"
    nonisolated static let paceTargetCreditIDKey = "paceTargetCreditID"

    let provider: UsageProvider
    @Published private(set) var requiresLogin = false
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var forecast: Forecast?
    @Published private(set) var samples: [UsageSample] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var syncFolderName: String?
    @Published private(set) var syncErrorMessage: String?

    private var stateKey: String { provider.preferenceKey("usageState") }
    private static let historyInstallationIDKey = "historyInstallationID"
    private var historySyncBookmarkKey: String { provider.preferenceKey("historySyncBookmark") }
    private let defaults: UserDefaults
    private let fetchUsage: @Sendable (Bool) async throws -> UsageSnapshot
    private let recoveryDelaysNanoseconds: [UInt64]
    private let sleepBeforeRecovery: @Sendable (UInt64) async throws -> Void
    private let history: UsageHistory
    private let widgetStore: WeeklyWidgetStore?
    private var previousStatus: PaceStatus?
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var started = false
    private var historyPrepared = false
    private var historyUsesFiles = false
    private var configuredSyncDirectory: URL?
    private var historyConnectionActive = false

    init(
        provider: UsageProvider = .codex,
        defaults: UserDefaults = .standard,
        historyDirectory: URL? = nil,
        historyNow: @escaping @Sendable () -> Date = { Date() },
        widgetStore: WeeklyWidgetStore? = nil,
        fetchUsage: (@Sendable () async throws -> UsageSnapshot)? = nil,
        recoveryDelaysNanoseconds: [UInt64] = [
            2_000_000_000,
            10_000_000_000,
            30_000_000_000
        ],
        sleepBeforeRecovery: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        },
        startsAutomatically: Bool = true
    ) {
        self.provider = provider
        self.defaults = defaults
        self.widgetStore = widgetStore ?? .shared(provider: provider) ?? WeeklyWidgetStore(
            directory: (historyDirectory ?? Self.historyDirectory(provider: provider))
                .appendingPathComponent("WeeklyWidget", isDirectory: true),
            provider: provider
        )
        if let fetchUsage {
            self.fetchUsage = { _ in try await fetchUsage() }
        } else {
            self.fetchUsage = { try await provider.fetchUsage(allowCredentialPrompt: $0) }
        }
        self.recoveryDelaysNanoseconds = recoveryDelaysNanoseconds
        self.sleepBeforeRecovery = sleepBeforeRecovery
        if let data = defaults.data(forKey: provider.preferenceKey("usageState")),
           let state = try? JSONDecoder().decode(StoredState.self, from: data) {
            snapshot = state.snapshot
            samples = state.samples
            previousStatus = state.previousStatus
        }

        let installationID: String
        if let existing = defaults.string(forKey: Self.historyInstallationIDKey),
           let uuid = UUID(uuidString: existing) {
            installationID = uuid.uuidString.lowercased()
        } else {
            installationID = UUID().uuidString.lowercased()
            defaults.set(installationID, forKey: Self.historyInstallationIDKey)
        }
        history = UsageHistory(
            localDirectory: historyDirectory ?? Self.historyDirectory(provider: provider),
            installationID: installationID,
            now: historyNow
        )
        recalculate()

        if startsAutomatically {
            Task { [weak self] in
                await self?.start()
            }
        }
    }

    var menuBarText: String {
        Self.menuBarText(remainingPercent: snapshot?.mainLimit.window.remainingPercent)
    }

    var weeklyWidgetSnapshot: WeeklyWidgetSnapshot? { widgetStore?.read() }

    var currentWindowSamples: [UsageSample] {
        Self.windowSamples(samples, reset: snapshot?.mainLimit.window.resetsAt)
    }

    nonisolated static func menuBarText(remainingPercent: Double?) -> String {
        guard let remainingPercent else { return "—" }
        return "\(Int(remainingPercent.rounded()))%"
    }

    nonisolated static func windowSamples(_ samples: [UsageSample], reset: Date?) -> [UsageSample] {
        guard let reset else { return [] }
        return samples
            .filter { UsageWindow.hasSameReset($0.resetsAt, reset) }
            .sorted { $0.observedAt < $1.observedAt }
    }

    func start() async {
        guard !started else { return }
        started = true

        await prepareHistory()

        Timer.publish(every: 600, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            .store(in: &cancellables)

        await refresh()
    }

    func refresh(allowCredentialPrompt: Bool = false) async {
        recoveryTask?.cancel()
        recoveryTask = nil
        await refresh(recoveryAttempt: 0, allowCredentialPrompt: allowCredentialPrompt)
    }

    private func refresh(recoveryAttempt: Int, allowCredentialPrompt: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await prepareHistory()
        if !historyUsesFiles {
            let historyState = await history.load(legacySamples: samples)
            apply(historyState)
            historyUsesFiles = historyState.errorMessage == nil
        }

        let fetchUsage = self.fetchUsage
        let fetchTask = Task { try await fetchUsage(allowCredentialPrompt) }
        let historyState = await exchangeHistory()
        apply(historyState, configuredFolderName: configuredSyncDirectory?.lastPathComponent)
        let exchangeErrorMessage = historyState.errorMessage
        recalculate()
        persist()

        do {
            let newSnapshot = try await fetchTask.value
            let window = newSnapshot.mainLimit.window
            let sample = UsageSample(
                observedAt: newSnapshot.fetchedAt,
                remainingPercent: window.remainingPercent,
                resetsAt: window.resetsAt,
                durationMinutes: window.durationMinutes
            )
            let recordedState = await history.record(sample)
            apply(recordedState, configuredFolderName: configuredSyncDirectory?.lastPathComponent)
            if recordedState.errorMessage == nil {
                syncErrorMessage = exchangeErrorMessage
            }
            snapshot = newSnapshot
            WeeklyWidgetPublisher.publish(newSnapshot, writer: .app, store: widgetStore,
                                          safetyBuffer: defaults.object(forKey: Self.safetyBufferKey) as? Double ?? 3,
                                          provider: provider)
            errorMessage = nil
            requiresLogin = false
            recalculate()
            persist()
        } catch let error as any UsageFetchError {
            errorMessage = error.localizedDescription
            requiresLogin = error.requiresLogin
            if error.shouldRetryAutomatically {
                scheduleRecovery(afterFailedAttempt: recoveryAttempt)
            }
        } catch {
            errorMessage = "Couldn’t load \(provider.displayName) usage. Refresh to try again."
            requiresLogin = false
            scheduleRecovery(afterFailedAttempt: recoveryAttempt)
        }
    }

    private func scheduleRecovery(afterFailedAttempt attempt: Int) {
        guard attempt < recoveryDelaysNanoseconds.count else { return }
        let delay = recoveryDelaysNanoseconds[attempt]
        let sleepBeforeRecovery = self.sleepBeforeRecovery
        recoveryTask?.cancel()
        recoveryTask = Task { [weak self] in
            do {
                try await sleepBeforeRecovery(delay)
                try Task.checkCancellation()
            } catch {
                return
            }
            guard let self else { return }
            recoveryTask = nil
            await refresh(recoveryAttempt: attempt + 1)
        }
    }

    func updateSafetyBuffer(_ value: Double) {
        if let snapshot {
            WeeklyWidgetPublisher.publish(snapshot, writer: .app, store: widgetStore, safetyBuffer: value, provider: provider)
        }
        recalculate(safetyBuffer: value)
        persist()
    }

    func updatePaceTarget(_ selectedCreditID: String) {
        defaults.set(selectedCreditID, forKey: provider.preferenceKey(Self.paceTargetCreditIDKey))
        recalculate(selectedCreditID: selectedCreditID)
        persist()
    }

    func connectHistoryFolder(_ directory: URL) async {
        await prepareHistory()
        let state = await history.connect(to: directory, subdirectory: provider.historySubdirectory)
        apply(state)
        historyConnectionActive = state.folderName != nil
        guard historyConnectionActive else { return }

        do {
            let bookmark = try directory.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: historySyncBookmarkKey)
            configuredSyncDirectory = directory
            syncFolderName = directory.lastPathComponent
        } catch {
            _ = await history.disconnect()
            configuredSyncDirectory = nil
            historyConnectionActive = false
            syncFolderName = nil
            syncErrorMessage = "Couldn’t save access to the history folder. Choose it again."
        }
    }

    func stopHistorySync() async {
        defaults.removeObject(forKey: historySyncBookmarkKey)
        configuredSyncDirectory = nil
        historyConnectionActive = false
        apply(await history.disconnect())
    }

    private func recalculate(
        safetyBuffer: Double? = nil,
        selectedCreditID: String? = nil
    ) {
        guard let snapshot else { return }
        let storedBuffer = defaults.object(forKey: Self.safetyBufferKey) as? Double
        let buffer = safetyBuffer ?? storedBuffer ?? 3
        let result = ForecastEngine.evaluate(
            window: snapshot.mainLimit.window,
            samples: samples,
            tokenHistory: snapshot.tokenHistory,
            safetyBuffer: buffer,
            now: snapshot.fetchedAt,
            previousStatus: previousStatus,
            deadline: ForecastEngine.paceDeadline(
                window: snapshot.mainLimit.window,
                resetCredits: snapshot.resetCredits,
                now: snapshot.fetchedAt,
                selectedCreditID: selectedCreditID
                    ?? defaults.string(forKey: provider.preferenceKey(Self.paceTargetCreditIDKey))
            )
        )
        forecast = result
        previousStatus = result.status
    }

    private func persist() {
        // A bounded copy of real samples is always persisted, so a cold launch
        // renders the charts at full fidelity instead of falling back to the
        // coarse daily token bootstrap while file history loads.
        let state = StoredState(
            snapshot: snapshot,
            samples: Self.samplesForPersistence(samples),
            previousStatus: previousStatus
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    private func prepareHistory() async {
        guard !historyPrepared else { return }
        historyPrepared = true

        let state = await history.load(legacySamples: samples)
        apply(state)
        historyUsesFiles = state.errorMessage == nil
        if historyUsesFiles {
            persist()
        }

        guard let bookmark = defaults.data(forKey: historySyncBookmarkKey) else {
            return
        }
        let directory: URL
        var isStale = false
        do {
            directory = try URL(
                resolvingBookmarkData: bookmark,
                options: [.withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
        } catch {
            defaults.removeObject(forKey: historySyncBookmarkKey)
            syncErrorMessage = "Couldn’t access the history folder. Choose it again."
            return
        }

        configuredSyncDirectory = directory
        let connectedState = await history.connect(to: directory, subdirectory: provider.historySubdirectory)
        historyConnectionActive = connectedState.folderName != nil
        apply(connectedState, configuredFolderName: directory.lastPathComponent)
        if isStale, historyConnectionActive {
            do {
                let refreshed = try directory.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(refreshed, forKey: historySyncBookmarkKey)
            } catch {
                syncErrorMessage = "Couldn’t renew access to the history folder. Choose it again."
            }
        }
    }

    private func exchangeHistory() async -> UsageHistory.State {
        if let configuredSyncDirectory, !historyConnectionActive {
            let state = await history.connect(to: configuredSyncDirectory, subdirectory: provider.historySubdirectory)
            historyConnectionActive = state.folderName != nil
            return state
        }
        return await history.synchronize()
    }

    private func apply(
        _ state: UsageHistory.State,
        configuredFolderName: String? = nil
    ) {
        // Merge instead of replace: a partial or failed history read must
        // never shrink what the charts already know within this session.
        samples = Self.mergedSamples(samples, state.samples)
        syncFolderName = configuredFolderName ?? state.folderName
        syncErrorMessage = state.errorMessage
    }

    /// Union of both sample sets, deduplicated, restricted to the retention
    /// window, in the stable order the charts and forecast expect. Retention
    /// is measured from the newest sample, not the wall clock, so the result
    /// is self-consistent whatever the clock says.
    nonisolated static func mergedSamples(
        _ current: [UsageSample],
        _ incoming: [UsageSample]
    ) -> [UsageSample] {
        let union = Array(Set(current + incoming))
        guard let newest = union.map(\.observedAt).max() else { return [] }
        let cutoff = newest.addingTimeInterval(-90 * 86_400)
        return union
            .filter { $0.observedAt >= cutoff }
            .sorted(by: sampleOrder)
    }

    /// The trailing 30 days (what the charts can show), capped so the stored
    /// state stays small; the newest samples win when the cap bites.
    nonisolated static func samplesForPersistence(_ samples: [UsageSample]) -> [UsageSample] {
        guard let newest = samples.map(\.observedAt).max() else { return [] }
        let cutoff = newest.addingTimeInterval(-30 * 86_400)
        let recent = samples
            .filter { $0.observedAt >= cutoff }
            .sorted(by: sampleOrder)
        return Array(recent.suffix(4_000))
    }

    private nonisolated static func sampleOrder(_ lhs: UsageSample, _ rhs: UsageSample) -> Bool {
        if lhs.observedAt != rhs.observedAt { return lhs.observedAt < rhs.observedAt }
        if lhs.remainingPercent != rhs.remainingPercent {
            return lhs.remainingPercent > rhs.remainingPercent
        }
        return lhs.resetsAt < rhs.resetsAt
    }

    nonisolated static func historyDirectory(provider: UsageProvider = .codex) -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? LegacyBundleMigration.legacyIdentifier,
                isDirectory: true
            )
            .appendingPathComponent(provider == .codex ? "History" : "ClaudeHistory", isDirectory: true)
    }
}

private struct StoredState: Codable {
    let snapshot: UsageSnapshot?
    let samples: [UsageSample]
    let previousStatus: PaceStatus?
}
