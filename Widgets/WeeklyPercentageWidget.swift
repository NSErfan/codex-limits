import CodexWidgetKit
import SwiftUI
import WidgetKit

struct WeeklyPercentageWidget: Widget {
    let kind = WeeklyWidgetStore.percentageKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyWidgetProvider()) { entry in
            WeeklyPercentageView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: entry.snapshot?.window?.remainingPercent)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
        }
        .configurationDisplayName("Weekly allowance")
        .description("See your remaining weekly Codex allowance and pace status.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
