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
    @Published private var periodSamples: [UsagePeriod: [UsageSample]] = [:]
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var refreshMessage: String?
    @Published private(set) var syncFolderName: String?
    @Published private(set) var syncErrorMessage: String?

    private var stateKey: String { provider.preferenceKey("usageState") }
    private static let historyInstallationIDKey = "historyInstallationID"
    private var historySyncBookmarkKey: String { provider.preferenceKey("historySyncBookmark") }
    private let defaults: UserDefaults
    private let fetchUsage: @Sendable () async throws -> UsageFetchResult
    private let recoveryDelaysNanoseconds: [UInt64]
    private let sleepBeforeRecovery: @Sendable (UInt64) async throws -> Void
    private let history: UsageHistory
    private let periodHistory: UsagePeriodHistory
    private let widgetStore: WeeklyWidgetStore?
    private var previousStatus: PaceStatus?
    private var cancellables: Set<AnyCancellable> = []
    private var recoveryTask: Task<Void, Never>?
    private var automaticRefreshTask: Task<Void, Never>?
    private var started = false
    private var historyPrepared = false
    private var historyUsesFiles = false
    private var periodHistoryUsesFiles = false
    private var configuredSyncDirectory: URL?
    private var historyConnectionActive = false

    init(
        provider: UsageProvider = .codex,
        defaults: UserDefaults = .standard,
        historyDirectory: URL? = nil,
        historyNow: @escaping @Sendable () -> Date = { Date() },
        widgetStore: WeeklyWidgetStore? = nil,
        fetchUsage: (@Sendable () async throws -> UsageSnapshot)? = nil,
        fetchResult: (@Sendable () async throws -> UsageFetchResult)? = nil,
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
        if let fetchResult {
            self.fetchUsage = fetchResult
        } else if let fetchUsage {
            self.fetchUsage = { .fetched(try await fetchUsage()) }
        } else {
            self.fetchUsage = { try await provider.fetchUsage() }
        }
        self.recoveryDelaysNanoseconds = recoveryDelaysNanoseconds
        self.sleepBeforeRecovery = sleepBeforeRecovery
        if let data = defaults.data(forKey: provider.preferenceKey("usageState")),
           let state = try? JSONDecoder().decode(StoredState.self, from: data) {
            snapshot = state.snapshot
            samples = state.samples
            periodSamples = state.periodSamples ?? [:]
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
        periodHistory = UsagePeriodHistory(
            localDirectory: historyDirectory ?? Self.historyDirectory(provider: provider),
            installationID: installationID,
            provider: provider,
            now: historyNow
        )
        if provider.periods.contains(.weekly) {
            periodSamples[.weekly] = Self.mergedSamples(
                periodSamples[.weekly] ?? [],
                Self.weeklySamples(from: self.widgetStore, provider: provider)
            )
        }
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

    func samples(for period: UsagePeriod) -> [UsageSample] {
        let saved = samples + (periodSamples[period] ?? [])
        let matching = saved.filter { period.includes(durationMinutes: $0.durationMinutes) }
        let observation = snapshot?.sample(for: period, provider: provider)
        return Self.mergedSamples(matching, observation.map { [$0] } ?? [])
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

    private nonisolated static func weeklySamples(
        from store: WeeklyWidgetStore?,
        provider: UsageProvider
    ) -> [UsageSample] {
        guard let store, store.provider == provider, let snapshot = store.read(),
              snapshot.status(at: snapshot.fetchedAt) != .unavailable,
              let window = snapshot.window,
              window.resetsAt.timeIntervalSince(window.startsAt) == Double(UsagePeriod.weekly.durationMinutes) * 60
        else { return [] }
        return snapshot.samples.filter {
            $0.date >= window.startsAt && $0.date <= snapshot.fetchedAt
                && $0.remainingPercent.isFinite && (0 ... 100).contains($0.remainingPercent)
        }.map {
            UsageSample(
                observedAt: $0.date,
                remainingPercent: $0.remainingPercent,
                resetsAt: window.resetsAt,
                durationMinutes: UsagePeriod.weekly.durationMinutes
            )
        }
    }

    func start() async {
        guard !started else { return }
        started = true

        await prepareHistory()

        if provider.refreshSchedule == .fixedInterval {
            Timer.publish(every: provider.refreshInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    Task { @MainActor in await self?.refresh() }
                }
                .store(in: &cancellables)
        }

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refresh() }
            }
            .store(in: &cancellables)

        await refresh()
    }

    @discardableResult
    func refresh() async -> Bool {
        recoveryTask?.cancel()
        recoveryTask = nil
        return await refresh(recoveryAttempt: 0)
    }

    @discardableResult
    private func refresh(recoveryAttempt: Int) async -> Bool {
        guard !isRefreshing else { return false }
        isRefreshing = true
        var nextAutomaticRefresh: Date?
        defer {
            isRefreshing = false
            scheduleAutomaticRefresh(at: nextAutomaticRefresh)
        }

        await prepareHistory()
        if !historyUsesFiles || !periodHistoryUsesFiles {
            await loadHistory()
        }

        let fetchUsage = self.fetchUsage
        let fetchTask = Task { try await fetchUsage() }
        let historyState = await exchangeHistory()
        apply(historyState.legacy, periodState: historyState.periods,
              configuredFolderName: configuredSyncDirectory?.lastPathComponent)
        let exchangeErrorMessage = historyState.legacy.errorMessage ?? historyState.periods.errorMessage
        recalculate()
        persist()

        do {
            switch try await fetchTask.value {
            case let .fetched(newSnapshot, nextRefreshAt):
                nextAutomaticRefresh = nextRefreshAt
                await accept(newSnapshot, exchangeErrorMessage: exchangeErrorMessage)
                errorMessage = nil
                refreshMessage = nil
                requiresLogin = false
                return true
            case let .cached(cached, nextRefreshAt):
                nextAutomaticRefresh = nextRefreshAt
                await accept(cached, exchangeErrorMessage: exchangeErrorMessage)
                refreshMessage = "Using saved \(provider.displayName) usage. Next check available \(nextRefreshAt.formatted(date: .abbreviated, time: .shortened))."
                errorMessage = nil
                requiresLogin = false
            case let .deferred(error, cached, nextRefreshAt):
                nextAutomaticRefresh = nextRefreshAt
                if let cached { await accept(cached, exchangeErrorMessage: exchangeErrorMessage) }
                applyFetchError(error, recoveryAttempt: recoveryAttempt)
            }
        } catch let error as any UsageFetchError {
            applyFetchError(error, recoveryAttempt: recoveryAttempt)
        } catch {
            errorMessage = "Couldn’t load \(provider.displayName) usage. Refresh to try again."
            refreshMessage = nil
            requiresLogin = false
            scheduleRecovery(afterFailedAttempt: recoveryAttempt)
        }
        return false
    }

    private func accept(_ newSnapshot: UsageSnapshot, exchangeErrorMessage: String?) async {
        guard snapshot == nil || newSnapshot.fetchedAt >= snapshot!.fetchedAt else { return }
        if newSnapshot != snapshot {
            let window = newSnapshot.mainLimit.window
            let sample = UsageSample(observedAt: newSnapshot.fetchedAt,
                                     remainingPercent: window.remainingPercent,
                                     resetsAt: window.resetsAt,
                                     durationMinutes: window.durationMinutes)
            let recordedState = await history.record(sample)
            let periodState = await periodHistory.record(newSnapshot)
            apply(recordedState, periodState: periodState,
                  configuredFolderName: configuredSyncDirectory?.lastPathComponent)
            if syncErrorMessage == nil { syncErrorMessage = exchangeErrorMessage }
            snapshot = newSnapshot
            WeeklyWidgetPublisher.publish(newSnapshot, writer: .app, store: widgetStore,
                                          safetyBuffer: defaults.object(forKey: Self.safetyBufferKey) as? Double ?? 3,
                                          provider: provider)
        }
        recalculate()
        persist()
    }

    private func applyFetchError(_ error: any UsageFetchError, recoveryAttempt: Int) {
        errorMessage = error.localizedDescription
        refreshMessage = nil
        requiresLogin = error.requiresLogin
        if error.shouldRetryAutomatically { scheduleRecovery(afterFailedAttempt: recoveryAttempt) }
    }

    private func scheduleAutomaticRefresh(at date: Date?) {
        guard started, provider.refreshSchedule == .fetchDeadline else { return }
        automaticRefreshTask?.cancel()
        // Long server deadlines remain in the shared gate; wake at least daily
        // to re-read them without converting an unbounded header into Duration.
        let delay = min(max(date?.timeIntervalSinceNow ?? provider.refreshInterval, 1), 86_400)
        automaticRefreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            automaticRefreshTask = nil
            await refresh()
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
        await stopHistorySync()
        let state = await history.connect(to: directory, subdirectory: provider.historySubdirectory)
        apply(state)
        historyConnectionActive = state.folderName != nil
        guard historyConnectionActive else { return }
        apply(state, periodState: await periodHistory.connect(to: directory),
              configuredFolderName: directory.lastPathComponent)

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
            _ = await periodHistory.disconnect()
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
        let state = await history.disconnect()
        apply(state, periodState: await periodHistory.disconnect())
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
            previousStatus: previousStatus,
            periodSamples: periodSamples.mapValues(Self.samplesForPersistence)
        )
        if let data = try? JSONEncoder().encode(state) {
            defaults.set(data, forKey: stateKey)
        }
    }

    private func prepareHistory() async {
        guard !historyPrepared else { return }
        historyPrepared = true

        await loadHistory()

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
        let periodState = historyConnectionActive ? await periodHistory.connect(to: directory) : nil
        apply(connectedState, periodState: periodState, configuredFolderName: directory.lastPathComponent)
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

    private func loadHistory() async {
        let state = await history.load(legacySamples: samples)
        let periodState = await periodHistory.load(
            legacySamples: Self.mergedSamples(samples, state.samples),
            savedSamples: periodSamples,
            snapshot: snapshot
        )
        apply(state, periodState: periodState)
        historyUsesFiles = state.errorMessage == nil
        periodHistoryUsesFiles = periodState.errorMessage == nil
        if historyUsesFiles && periodHistoryUsesFiles { persist() }
    }

    private func exchangeHistory() async -> (legacy: UsageHistory.State, periods: UsagePeriodHistory.State) {
        if let configuredSyncDirectory, !historyConnectionActive {
            let state = await history.connect(to: configuredSyncDirectory, subdirectory: provider.historySubdirectory)
            historyConnectionActive = state.folderName != nil
            let periods = historyConnectionActive
                ? await periodHistory.connect(to: configuredSyncDirectory)
                : await periodHistory.synchronize()
            return (state, periods)
        }
        let state = await history.synchronize()
        return (state, await periodHistory.synchronize())
    }

    private func apply(
        _ state: UsageHistory.State,
        periodState: UsagePeriodHistory.State? = nil,
        configuredFolderName: String? = nil
    ) {
        // Merge instead of replace: a partial or failed history read must
        // never shrink what the charts already know within this session.
        samples = Self.mergedSamples(samples, state.samples)
        for (period, incoming) in periodState?.samples ?? [:] {
            periodSamples[period] = Self.mergedSamples(
                periodSamples[period] ?? [],
                incoming.filter { period.includes(durationMinutes: $0.durationMinutes) }
            )
        }
        syncFolderName = configuredFolderName ?? state.folderName
        syncErrorMessage = state.errorMessage ?? periodState?.errorMessage
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
            .appendingPathComponent(provider.localHistoryDirectoryName, isDirectory: true)
    }
}

private struct StoredState: Codable {
    let snapshot: UsageSnapshot?
    let samples: [UsageSample]
    let previousStatus: PaceStatus?
    let periodSamples: [UsagePeriod: [UsageSample]]?
}
