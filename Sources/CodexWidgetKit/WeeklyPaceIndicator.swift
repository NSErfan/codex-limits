import SwiftUI

struct WeeklyPaceIndicator: View {
    let pace: WeeklyPace
    @Environment(\.colorScheme) private var scheme

    private var symbol: String {
        switch pace {
        case .slowDown: "gauge.with.dots.needle.67percent"
        case .onTrack: "checkmark"
        case .roomToUseMore: "arrow.up.right"
        }
    }

    private var color: Color {
        switch pace {
        case .slowDown: scheme == .dark ? .orange : Color(red: 0.65, green: 0.30, blue: 0)
        case .onTrack: scheme == .dark ? .mint : Color(red: 0, green: 0.43, blue: 0.30)
        case .roomToUseMore: scheme == .dark ? .cyan : .blue
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 20, height: 20)
            .background(color.opacity(0.12), in: Circle())
            .help("Weekly pace: \(pace.title)")
            .accessibilityLabel("Weekly pace: \(pace.title)")
    }
}
