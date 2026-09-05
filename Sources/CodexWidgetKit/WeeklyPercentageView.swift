import SwiftUI

public struct WeeklyPercentageView: View {
    public let snapshot: WeeklyWidgetSnapshot?
    public let date: Date
    @Environment(\.colorScheme) private var scheme

    public init(snapshot: WeeklyWidgetSnapshot?, date: Date) {
        self.snapshot = snapshot
        self.date = date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WeeklyWidgetHeader(stale: status == .stale)
            Spacer(minLength: 4)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(remaining.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: 57, weight: .medium, design: .rounded))
                    .tracking(-3)
                    .monospacedDigit()
                if remaining != nil {
                    Text("%")
                        .font(.system(size: 25, weight: .regular, design: .rounded))
                        .foregroundStyle(accent)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            Text(caption)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 10)
            HStack(spacing: 3) {
                ForEach(0 ..< 24) { tick in
                    Capsule()
                        .fill(Double(tick) < (remaining ?? 0) / 100 * 24 ? accent : Color.primary.opacity(0.09))
                }
            }
            .frame(height: 10)
            .accessibilityHidden(true)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Codex weekly limit")
        .accessibilityValue(accessibilityValue)
    }

    private var status: WeeklyWidgetSnapshot.Status { snapshot?.status(at: date) ?? .unavailable }
    private var remaining: Double? {
        status == .current || status == .stale ? snapshot?.window?.remainingPercent : nil
    }
    private var accent: Color { WeeklyWidgetStyle.accent(for: remaining, scheme: scheme) }
    private var caption: String {
        switch status {
        case .current: "Weekly remaining"
        case .stale: "Weekly · last known"
        case .expired: "Reset reached · refresh app"
        case .unavailable: "Open app to get started"
        }
    }
    private var accessibilityValue: String {
        if let remaining {
            return "\(Int(remaining.rounded())) percent remaining\(status == .stale ? ", last known reading" : "")"
        }
        return caption
    }
}
