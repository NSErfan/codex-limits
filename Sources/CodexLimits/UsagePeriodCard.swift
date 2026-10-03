import CodexWidgetKit
import SwiftUI

struct UsagePeriodCard: View {
    let period: UsagePeriod
    let window: UsageWindow?
    let isSelected: Bool
    var now: Date = .now
    var select: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    private var accent: Color {
        UsageChartStyle.accent(for: window?.remainingPercent, scheme: colorScheme, selection: usageAccent)
    }

    private var hasExpired: Bool { window.map { $0.resetsAt <= now } ?? false }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(period.title.uppercased())
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                    Spacer(minLength: 4)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isSelected ? accent : .secondary)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                if let window {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(Int(window.remainingPercent.rounded()))%")
                            .font(.system(size: 29, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        Text(hasExpired ? "last reading" : "remaining")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if hasExpired {
                            Text("Awaiting next reading")
                                .fontWeight(.medium)
                        }
                        Text("\(hasExpired ? "Reset passed" : "Resets") \(window.resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .font(.system(size: 10))
                    .frame(height: 26, alignment: .topLeading)
                } else {
                    Text("Not reported")
                        .font(.system(size: 17, weight: .medium))
                        .padding(.vertical, 5)
                    Text("No account limit available")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(height: 26, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(accent.opacity(isSelected ? 0.10 : 0.025), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? accent.opacity(0.65) : Color.secondary.opacity(0.18), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .disabled(window == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityHint(window == nil ? "" : hasExpired ? "Show recorded history for this period." : "Show this period’s chart and pacing details.")
        .help(window == nil ? "This account limit was not reported." : hasExpired ? "Show recorded history for this period." : "Show \(period.title.lowercased()) chart and pacing details.")
    }

    private var accessibilityLabel: String {
        guard let window else { return "\(period.title) limit, not reported" }
        if hasExpired {
            return "\(period.title) limit, last reading \(Int(window.remainingPercent.rounded())) percent, reset passed \(window.resetsAt.formatted(date: .abbreviated, time: .shortened)), awaiting next reading"
        }
        return "\(period.title) limit, \(Int(window.remainingPercent.rounded())) percent remaining, resets \(window.resetsAt.formatted(date: .abbreviated, time: .shortened))"
    }
}
