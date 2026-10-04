import CodexWidgetKit
import SwiftUI
import WidgetKit

struct ClaudeWeeklyGraphWidget: Widget {
    let kind = WeeklyWidgetStore.graphKind(for: .claude)

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyWidgetProvider(provider: .claude)) { entry in
            WeeklyGraphView(snapshot: entry.snapshot, date: entry.date, provider: .claude)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: entry.snapshot?.window?.remainingPercent)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
                .widgetURL(URL(string: "codexlimits://usage/claude"))
        }
        .configurationDisplayName("Claude Code weekly usage chart")
        .description("Track your weekly Claude Code allowance across all models against an even pace to reset.")
        .supportedFamilies([.systemMedium])
        .contentMarginsDisabled()
    }
}
