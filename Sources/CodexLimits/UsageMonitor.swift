import AppKit
import Combine
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    nonisolated static let safetyBufferKey = "safetyBuffer"
    nonisolated static let paceTargetCreditIDKey = "paceTargetCreditID"

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var forecast: Forecast?
    @Published private(set) var samples: [UsageSample] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var syncFolderName: String?
    @Published private(set) var syncErrorMessage: String?

    private static let stateKey = "usageState"
    private static let historyInstallationIDKey = "historyInstallationID"
    private static let historySyncBookmarkKey = "historySyncBookmark"
    private let defaults: UserDefaults
    private let fetchUsage: @Sendable () async throws -> UsageSnapshot
    private let history: UsageHistory
    private var previousStatus: PaceStatus?
    private var cancellables: Set<AnyCancellable> = []
    private var started = false
    private var historyPrepared = false
    private var historyUsesFiles = false
    private var configuredSyncDirectory: URL?
    private var historyConnectionActive = false

    init(
        defaults: UserDefaults = .standard,
        historyDirectory: URL? = nil,
        historyNow: @escaping @Sendable () -> Date = { Date() },
        fetchUsage: @escaping @Sendable () async throws -> UsageSnapshot = {
            try await CodexClient.fetch()
        },
        startsAutomatically: Bool = true
    ) {
        self.defaults = defaults
        self.fetchUsage = fetchUsage
        if let data = defaults.data(forKey: Self.stateKey),
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
            localDirectory: historyDirectory ?? Self.historyDirectory(),
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

    var currentWindowSamples: [UsageSample] {
        Self.windowSamples(samples, reset: snapshot?.mainLimit.window.resetsAt)
    }

    nonisolated static func menuBarText(remainingPercent: Double?) -> String {
        guard let remainingPercent else { return "—" }
        return "\(Int(remainingPercent.rounded()))%"
    }

    nonisolated static func windowSamples(_ samples: [UsageSample], reset: Date?) -> [UsageSample] {
        guard let reset else { return [] }
        return samples.filter { $0.resetsAt == reset }.sorted { $0.observedAt < $1.observedAt }
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

    func refresh() async {
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
        let fetchTask = Task { try await fetchUsage() }
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
                resetsAt: window.resetsAt
            )
            let recordedState = await history.record(sample)
            apply(recordedState, configuredFolderName: configuredSyncDirectory?.lastPathComponent)
            if recordedState.errorMessage == nil {
                syncErrorMessage = exchangeErrorMessage
            }
            snapshot = newSnapshot
            errorMessage = nil
            recalculate()
            persist()
        } catch let error as CodexClientError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Couldn’t read Codex usage. Try refreshing again."
        }
    }

    func updateSafetyBuffer(_ value: Double) {
        recalculate(safetyBuffer: value)
        persist()
    }

    func updatePaceTarget() {
        recalculate()
        persist()
    }

    func connectHistoryFolder(_ directory: URL) async {
        await prepareHistory()
        let state = await history.connect(to: directory)
        apply(state)
        historyConnectionActive = state.folderName != nil
        guard historyConnectionActive else { return }

        do {
            let bookmark = try directory.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            defaults.set(bookmark, forKey: Self.historySyncBookmarkKey)
            configuredSyncDirectory = directory
            syncFolderName = directory.lastPathComponent
        } catch {
            _ = await history.disconnect()
            configuredSyncDirectory = nil
            historyConnectionActive = false
            syncFolderName = nil
            syncErrorMessage = "Couldn’t remember the history folder. Choose it again."
        }
    }

    func stopHistorySync() async {
        defaults.removeObject(forKey: Self.historySyncBookmarkKey)
        configuredSyncDirectory = nil
        historyConnectionActive = false
        apply(await history.disconnect())
    }

    private func recalculate(safetyBuffer: Double? = nil) {
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
                selectedCreditID: defaults.string(forKey: Self.paceTargetCreditIDKey)
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
            defaults.set(data, forKey: Self.stateKey)
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

        guard let bookmark = defaults.data(forKey: Self.historySyncBookmarkKey) else {
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
            defaults.removeObject(forKey: Self.historySyncBookmarkKey)
            syncErrorMessage = "Couldn’t reopen the history folder. Choose it again."
            return
        }

        configuredSyncDirectory = directory
        let connectedState = await history.connect(to: directory)
        historyConnectionActive = connectedState.folderName != nil
        apply(connectedState, configuredFolderName: directory.lastPathComponent)
        if isStale, historyConnectionActive {
            do {
                let refreshed = try directory.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                defaults.set(refreshed, forKey: Self.historySyncBookmarkKey)
            } catch {
                syncErrorMessage = "Couldn’t update the saved history folder."
            }
        }
    }

    private func exchangeHistory() async -> UsageHistory.State {
        if let configuredSyncDirectory, !historyConnectionActive {
            let state = await history.connect(to: configuredSyncDirectory)
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
        syncFolderName = state.folderName ?? configuredFolderName
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

    private static func historyDirectory() -> URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent(
                Bundle.main.bundleIdentifier ?? LegacyBundleMigration.legacyIdentifier,
                isDirectory: true
            )
            .appendingPathComponent("History", isDirectory: true)
    }
}

private struct StoredState: Codable {
    let snapshot: UsageSnapshot?
    let samples: [UsageSample]
    let previousStatus: PaceStatus?
}
