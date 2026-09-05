import CodexWidgetKit
import Foundation
import OSLog
import WidgetKit

enum WeeklyWidgetPublisher {
    private static let logger = Logger(subsystem: "com.github.nserfan.CodexLimits", category: "Widgets")

    static func snapshot(from usage: UsageSnapshot) -> WeeklyWidgetSnapshot {
        // mainLimit is the most constrained window, not necessarily the week.
        let weekly = ([usage.mainLimit] + usage.otherLimits).first {
            $0.limitId == "codex" && $0.window.durationMinutes == 10_080
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
        return WeeklyWidgetSnapshot(fetchedAt: usage.fetchedAt, window: window)
            .merging([])
    }

    static func publish(
        _ usage: UsageSnapshot,
        writer: WeeklyWidgetStore.Writer,
        store: WeeklyWidgetStore?
    ) {
        guard let store else { return }
        do {
            try store.write(snapshot(from: usage), writer: writer)
            if Bundle.main.object(forInfoDictionaryKey: "CodexWidgetAppGroup") != nil {
                WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.percentageKind)
                WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.graphKind)
            }
        } catch {
            logger.error("Could not update weekly widgets: \(error.localizedDescription, privacy: .public)")
        }
    }
}
