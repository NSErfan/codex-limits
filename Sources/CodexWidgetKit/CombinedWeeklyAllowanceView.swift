import SwiftUI

public struct CombinedWeeklyAllowanceView: View {
    public let codex: WeeklyWidgetSnapshot?
    public let claude: WeeklyWidgetSnapshot?
    public let date: Date
    public let expanded: Bool
    /// Providers turned off in the app; their rows show no reading.
    public let disabledProviders: Set<UsageProvider>

    public init(
        codex: WeeklyWidgetSnapshot?, claude: WeeklyWidgetSnapshot?, date: Date, expanded: Bool = false,
        disabledProviders: Set<UsageProvider> = []
    ) {
        self.codex = codex
        self.claude = claude
        self.date = date
        self.expanded = expanded
        self.disabledProviders = disabledProviders
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
        let isTurnedOff = disabledProviders.contains(provider)
        let row = WeeklyAllowanceRow(snapshot: isTurnedOff ? nil : snapshot, date: date, provider: provider,
                                     expanded: expanded, isTurnedOff: isTurnedOff)
        if expanded, !isTurnedOff, let url = URL(string: "codexlimits://usage/\(provider.rawValue)") {
            Link(destination: url) { row }
                .buttonStyle(.plain)
        } else {
            row
        }
    }
}
