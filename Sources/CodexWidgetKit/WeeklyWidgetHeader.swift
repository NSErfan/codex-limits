import SwiftUI

struct WeeklyWidgetHeader: View {
    let stale: Bool
    var pace: WeeklyPace? = nil

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("CODEX")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
            Spacer(minLength: 4)
            if let pace {
                WeeklyPaceIndicator(pace: pace)
            }
            if stale {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .medium))
                    .accessibilityLabel("Reading is over 30 minutes old")
            }
        }
        .foregroundStyle(.secondary)
    }
}
