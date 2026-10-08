import CodexWidgetKit
import SwiftUI
import WidgetKit

struct ClaudeWeeklyPercentageWidget: Widget {
    let kind = WeeklyWidgetStore.percentageKind(for: .claude)

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeeklyWidgetProvider(provider: .claude)) { entry in
            WeeklyPercentageView(snapshot: entry.snapshot, date: entry.date, provider: .claude, isTurnedOff: entry.isTurnedOff)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: entry.snapshot?.window?.remainingPercent)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
                .widgetURL(URL(string: "codexlimits://usage/claude"))
        }
        .configurationDisplayName("Claude Code weekly allowance")
        .description("See your remaining weekly Claude Code allowance across all models and pace status.")
        .supportedFamilies([.systemSmall])
        .contentMarginsDisabled()
    }
}
