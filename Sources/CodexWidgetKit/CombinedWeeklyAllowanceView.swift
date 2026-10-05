import SwiftUI

public struct CombinedWeeklyAllowanceView: View {
    public let codex: WeeklyWidgetSnapshot?
    public let claude: WeeklyWidgetSnapshot?
    public let date: Date
    public let expanded: Bool

    public init(codex: WeeklyWidgetSnapshot?, claude: WeeklyWidgetSnapshot?, date: Date, expanded: Bool = false) {
        self.codex = codex
        self.claude = claude
        self.date = date
        self.expanded = expanded
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 12 : 8) {
            if expanded {
                Text("WEEKLY ALLOWANCE")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
            }
            allowance(snapshot: codex, provider: .codex)
            Rectangle().fill(.primary.opacity(0.1)).frame(height: 1)
                .accessibilityHidden(true)
            allowance(snapshot: claude, provider: .claude)
        }
        .padding(expanded ? 18 : 14)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Claude and Codex weekly allowances")
    }

    @ViewBuilder private func allowance(snapshot: WeeklyWidgetSnapshot?, provider: UsageProvider) -> some View {
        if expanded, let url = URL(string: "codexlimits://usage/\(provider.rawValue)") {
            Link(destination: url) {
                WeeklyAllowanceRow(snapshot: snapshot, date: date, provider: provider, expanded: true)
            }
            .buttonStyle(.plain)
        } else {
            WeeklyAllowanceRow(snapshot: snapshot, date: date, provider: provider, expanded: false)
        }
    }
}
