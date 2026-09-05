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
        .configurationDisplayName("Weekly Percentage")
        .description("Your remaining weekly Codex limit. One number, a little breathing room.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
