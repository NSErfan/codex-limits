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
        .configurationDisplayName("Weekly Graph")
        .description("Your weekly balance and usage curve, with an even-pace guide to reset.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
