import CodexWidgetKit
import SwiftUI
import WidgetKit

struct CombinedWeeklyAllowanceWidget: Widget {
    let kind = WeeklyWidgetStore.combinedKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CombinedWeeklyWidgetProvider()) { entry in
            Content(entry: entry)
                .containerBackground(for: .widget) {
                    UsageSurfaceBackground(remaining: nil)
                        .environment(\.usageAccent, entry.accent)
                }
                .environment(\.usageAccent, entry.accent)
                .widgetURL(URL(string: "codexlimits://usage/\(entry.linkedProvider.rawValue)"))
        }
        .configurationDisplayName("Claude + Codex allowance")
        .description("Both weekly allowances, with a suggested daily pace until each scheduled reset.")
        .supportedFamilies([.systemSmall, .systemLarge])
        .contentMarginsDisabled()
    }

    private struct Content: View {
        let entry: CombinedWeeklyWidgetProvider.Entry
        @Environment(\.widgetFamily) private var family

        var body: some View {
            CombinedWeeklyAllowanceView(
                codex: entry.codex, claude: entry.claude, date: entry.date, expanded: family == .systemLarge,
                disabledProviders: entry.disabledProviders
            )
        }
    }
}
