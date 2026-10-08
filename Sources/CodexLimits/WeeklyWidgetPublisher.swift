import CodexWidgetKit
import Foundation
import OSLog
import WidgetKit

enum WeeklyWidgetPublisher {
    private static let logger = Logger(subsystem: "com.github.nserfan.CodexLimits", category: "Widgets")

    static func snapshot(
        from usage: UsageSnapshot,
        previous: WeeklyWidgetSnapshot? = nil,
        safetyBuffer: Double = 3,
        provider: UsageProvider = .codex
    ) -> WeeklyWidgetSnapshot {
        // mainLimit is the most constrained window, not necessarily the week.
        let weekly = ([usage.mainLimit] + usage.otherLimits).first {
            $0.limitId == provider.rawValue && $0.window.durationMinutes == 10_080
        }?.window
        let window = weekly.map {
            WeeklyWidgetSnapshot.Window(
                remainingPercent: $0.remainingPercent,
                startsAt: $0.startsAt,
                resetsAt: $0.resetsAt
            )
        }
        // Legacy main-limit history has no window duration or limit identifier.
        // Five-hour and weekly resets can coincide, so it cannot safely seed this
        // chart. Only the dedicated weekly store provides earlier observations.
        let snapshot = WeeklyWidgetSnapshot(fetchedAt: usage.fetchedAt, window: window)
            .merging(previous.map { [$0] } ?? [])
        guard let weekly, snapshot.status(at: usage.fetchedAt) == .current else { return snapshot }
        let sameWindow = previous?.window.map { UsageWindow.hasSameReset($0.resetsAt, weekly.resetsAt) } ?? false
        let forecast = ForecastEngine.evaluate(
            window: weekly,
            samples: snapshot.samples.map {
                UsageSample(observedAt: $0.date, remainingPercent: $0.remainingPercent, resetsAt: weekly.resetsAt)
            },
            tokenHistory: usage.tokenHistory,
            safetyBuffer: safetyBuffer,
            now: usage.fetchedAt,
            previousStatus: sameWindow ? previous?.pace.map {
                switch $0 {
                case .slowDown: .slowDown
                case .onTrack: .onTrack
                case .roomToUseMore: .roomToUseMore
                }
            } : nil
        )
        let pace: WeeklyPace = switch forecast.status {
        case .slowDown: .slowDown
        case .onTrack: .onTrack
        case .roomToUseMore: .roomToUseMore
        }
        return WeeklyWidgetSnapshot(
            fetchedAt: snapshot.fetchedAt, window: window, samples: snapshot.samples,
            pace: pace, reservePercent: safetyBuffer
        )
    }

    static func reloadAllTimelines() {
        for provider in UsageProvider.allCases {
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.percentageKind(for: provider))
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.graphKind(for: provider))
        }
        WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.combinedKind)
    }

    static func publish(
        _ usage: UsageSnapshot,
        writer: WeeklyWidgetStore.Writer,
        store: WeeklyWidgetStore?,
        safetyBuffer: Double = 3,
        provider: UsageProvider = .codex
    ) {
        // Weekly widgets exist only for providers with a weekly allowance.
        guard let store, store.provider == provider, provider.periods.contains(.weekly) else { return }
        do {
            try store.write(
                snapshot(from: usage, previous: store.read(), safetyBuffer: safetyBuffer, provider: provider),
                writer: writer
            )
            if Bundle.main.object(forInfoDictionaryKey: "CodexWidgetAppGroup") != nil {
                WidgetCenter.shared.reloadTimelines(ofKind: store.percentageKind)
                WidgetCenter.shared.reloadTimelines(ofKind: store.graphKind)
                WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.combinedKind)
            }
        } catch {
            logger.error("Could not update weekly widgets: \(error.localizedDescription, privacy: .public)")
        }
    }
}
