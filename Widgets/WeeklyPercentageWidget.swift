import CodexWidgetKit
import SwiftUI
import WidgetKit

struct WeeklyPercentageWidget: Widget {
    let kind = WeeklyWidgetStore.percentageKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyWidgetProvider()) { entry in
            WeeklyPercentageView(snapshot: entry.snapshot, date: entry.date, isTurnedOff: entry.isTurnedOff)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: entry.snapshot?.window?.remainingPercent)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
                .widgetURL(URL(string: "codexlimits://usage/codex"))
        }
        .configurationDisplayName("Weekly allowance")
        .description("See your remaining weekly Codex allowance and pace status.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
