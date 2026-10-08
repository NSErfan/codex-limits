import SwiftUI

struct WeeklyAllowanceRow: View {
    let snapshot: WeeklyWidgetSnapshot?
    let date: Date
    let provider: UsageProvider
    let expanded: Bool
    /// The provider is turned off in the app; the caller passes no snapshot.
    var isTurnedOff = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.usageAccent) private var usageAccent

    var body: some View {
        VStack(alignment: .leading, spacing: expanded ? 6 : 2) {
            HStack(spacing: 5) {
                ProviderIcon(provider: provider, size: expanded ? 16 : 12)
                Text(provider.displayName)
                    .font(.system(size: expanded ? 12 : 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                Spacer(minLength: 2)
                Text(isTurnedOff ? "Off" : status == .stale ? "Saved" : "Weekly")
                    .font(.system(size: expanded ? 9 : 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(remaining.map { String(Int($0.rounded())) } ?? "—")
                    .font(.system(size: expanded ? 40 : 28, weight: .medium, design: .rounded))
                    .tracking(expanded ? -1.5 : -0.8)
                    .monospacedDigit()
                if remaining != nil {
                    Text("%")
                        .font(.system(size: expanded ? 20 : 15, design: .rounded))
                        .foregroundStyle(accent)
                    Text("left")
                        .font(.system(size: expanded ? 11 : 9))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 3)
                }
                Spacer(minLength: 0)
                if expanded, let pace = snapshot?.pace(at: date) {
                    WeeklyPaceIndicator(pace: pace)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Text(paceText)
                .font(.system(size: expanded ? 10 : 9, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if expanded {
                if let snapshot, remaining != nil {
                    WeeklyUsageChart(snapshot: snapshot, accent: accent)
                        .frame(maxHeight: .infinity)
                        .accessibilityHidden(true)
                } else {
                    Spacer(minLength: 0)
                }
                if remaining != nil, let reset = snapshot?.window?.resetsAt {
                    Text("Resets \(reset, format: .dateTime.weekday(.abbreviated).hour().minute())")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(accent)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: expanded ? .infinity : nil, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(provider.displayName) weekly allowance")
        .accessibilityValue(accessibilityValue)
    }

    private var status: WeeklyWidgetSnapshot.Status { snapshot?.status(at: date) ?? .unavailable }
    private var remaining: Double? {
        status == .current || status == .stale ? snapshot?.window?.remainingPercent : nil
    }
    private var accent: Color { UsageChartStyle.accent(for: remaining, scheme: scheme, selection: usageAccent) }
    private var paceText: String {
        if isTurnedOff { return "Turned off in Codex Limits" }
        if let pace = snapshot?.suggestedDailyPercent(at: date) {
            let roundedDown = floor(pace * 10) / 10
            return "\(roundedDown.formatted(.number.precision(.fractionLength(1))))%/day"
        }
        switch status {
        case .current: return "Refresh app for suggested pace"
        case .stale: return "Open app to refresh pace"
        case .expired: return "Reset passed · Refresh app"
        case .unavailable: return snapshot == nil ? "Connect \(provider.displayName) in app" : "Weekly usage unavailable"
        }
    }
    private var accessibilityValue: String {
        guard let remaining else { return paceText }
        let reset = snapshot?.window?.resetsAt.formatted(date: .abbreviated, time: .shortened) ?? "unknown"
        let statusText = snapshot?.pace(at: date).map { " \($0.title)." } ?? ""
        let paceDescription = snapshot?.suggestedDailyPercent(at: date) == nil
            ? paceText : "Suggested daily pace: \(paceText) until reset"
        return "\(Int(remaining.rounded())) percent remaining. \(paceDescription).\(statusText) Scheduled reset: \(reset)."
    }
}
