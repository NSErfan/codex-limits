import SwiftUI

struct WeeklyWidgetHeader: View {
    let stale: Bool
    var pace: WeeklyPace? = nil
    var provider: UsageProvider = .codex

    var body: some View {
        HStack(spacing: 6) {
            ProviderIcon(provider: provider, size: 12)
            Text(provider == .claude ? "CLAUDE" : "CODEX")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .accessibilityLabel(provider.displayName)
            Spacer(minLength: 4)
            if let pace {
                WeeklyPaceIndicator(pace: pace)
            }
            if stale {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityLabel("Last updated at least 30 minutes ago")
            }
        }
        .foregroundStyle(.secondary)
    }
}
