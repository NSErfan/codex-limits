import CodexWidgetKit
import SwiftUI
import WidgetKit

struct WeeklyGraphWidget: Widget {
    let kind = WeeklyWidgetStore.graphKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyWidgetProvider()) { entry in
            WeeklyGraphView(snapshot: entry.snapshot, date: entry.date)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: entry.snapshot?.window?.remainingPercent)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
        }
        .configurationDisplayName("Weekly usage chart")
        .description("Track your remaining weekly allowance against an even pace to the scheduled reset.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
