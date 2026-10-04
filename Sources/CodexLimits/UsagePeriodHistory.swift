import CodexWidgetKit
import Foundation

actor UsagePeriodHistory {
    struct State: Sendable {
        let samples: [UsagePeriod: [UsageSample]]
        let errorMessage: String?
    }

    private let histories: [UsagePeriod: UsageHistory]
    private let provider: UsageProvider
    private var syncDirectory: URL?
    private var connectedPeriods: Set<UsagePeriod> = []

    init(
        localDirectory: URL,
        installationID: String,
        provider: UsageProvider,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        histories = Dictionary(uniqueKeysWithValues: UsagePeriod.allCases.map { period in
            (period, UsageHistory(
                localDirectory: localDirectory.appendingPathComponent(Self.subdirectory(for: period)),
                installationID: installationID,
                now: now
            ))
        })
    }

    func load(
        legacySamples: [UsageSample],
        savedSamples: [UsagePeriod: [UsageSample]] = [:],
        snapshot: UsageSnapshot? = nil
    ) async -> State {
        var states: [UsagePeriod: UsageHistory.State] = [:]
        for period in UsagePeriod.allCases {
            let existing = legacySamples + (savedSamples[period] ?? [])
            let matching = existing.filter { $0.durationMinutes == period.durationMinutes }
            let observation = snapshot?.sample(for: period, provider: provider)
            states[period] = await histories[period]?.load(
                legacySamples: matching + (observation.map { [$0] } ?? [])
            )
        }
        return combined(states)
    }

    func record(_ snapshot: UsageSnapshot) async -> State {
        var states: [UsagePeriod: UsageHistory.State] = [:]
        for period in UsagePeriod.allCases {
            guard let sample = snapshot.sample(for: period, provider: provider) else { continue }
            states[period] = await histories[period]?.record(sample)
        }
        return combined(states)
    }

    func connect(to directory: URL) async -> State {
        syncDirectory = directory
        connectedPeriods = []
        return await synchronize()
    }

    func disconnect() async -> State {
        syncDirectory = nil
        connectedPeriods = []
        var states: [UsagePeriod: UsageHistory.State] = [:]
        for period in UsagePeriod.allCases {
            states[period] = await histories[period]?.disconnect()
        }
        return combined(states)
    }

    func synchronize() async -> State {
        var states: [UsagePeriod: UsageHistory.State] = [:]
        for period in UsagePeriod.allCases {
            if let syncDirectory, !connectedPeriods.contains(period) {
                let path = [provider.historySubdirectory, Self.subdirectory(for: period)]
                    .compactMap { $0 }.joined(separator: "/")
                let state = await histories[period]?.connect(to: syncDirectory, subdirectory: path)
                if state?.folderName != nil { connectedPeriods.insert(period) }
                states[period] = state
            } else {
                states[period] = await histories[period]?.synchronize()
            }
        }
        return combined(states)
    }

    private func combined(_ states: [UsagePeriod: UsageHistory.State]) -> State {
        State(
            samples: states.mapValues(\.samples),
            errorMessage: UsagePeriod.allCases.compactMap { states[$0]?.errorMessage }.first
        )
    }

    private nonisolated static func subdirectory(for period: UsagePeriod) -> String {
        "Windows/\(period.durationMinutes)"
    }
}
