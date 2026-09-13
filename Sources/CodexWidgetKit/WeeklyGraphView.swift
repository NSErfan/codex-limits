import SwiftUI

public struct WeeklyGraphView: View {
    public let snapshot: WeeklyWidgetSnapshot?
    public let date: Date
    @Environment(\.colorScheme) private var scheme
    @Environment(\.usageAccent) private var usageAccent

    public init(snapshot: WeeklyWidgetSnapshot?, date: Date) {
        self.snapshot = snapshot
        self.date = date
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                WeeklyWidgetHeader(stale: status == .stale, pace: snapshot?.pace(at: date))
                Text("WEEKLY LIMIT")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text(remaining.map { String(Int($0.rounded())) } ?? "—")
                            .font(.system(size: 44, weight: .medium, design: .rounded))
                            .tracking(-2)
                            .monospacedDigit()
                        if remaining != nil {
                            Text("%")
                                .font(.system(size: 20, design: .rounded))
                                .foregroundStyle(accent)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    Text(status == .stale ? "at last update" : "remaining")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    Text(resetText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(width: 100, alignment: .leading)
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 1)
                chart
            }
        }
        .padding(16)
    }

    @ViewBuilder private var chart: some View {
        if let snapshot, let window = snapshot.window, remaining != nil {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 5) {
                    Circle().fill(accent).frame(width: 4, height: 4)
                    Text(snapshot.samples.count < 2 ? "Building usage history" : "Remaining")
                    Spacer(minLength: 0)
                    Text("┄").foregroundStyle(.secondary)
                    Text("Even pace")
                }
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                WeeklyUsageChart(snapshot: snapshot, accent: accent)
                    .padding(.top, 2)
                HStack {
                    Text(window.startsAt, format: .dateTime.month(.abbreviated).day())
                    Spacer()
                    Text(window.resetsAt, format: .dateTime.month(.abbreviated).day())
                }
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: status == .expired ? "arrow.clockwise" : "chart.xyaxis.line")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(accent)
                Text(status == .expired ? "New reading needed" : "Weekly usage unavailable")
                    .font(.system(size: 11, weight: .medium))
                Text("Open Codex Limits to refresh your weekly allowance.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    private var status: WeeklyWidgetSnapshot.Status { snapshot?.status(at: date) ?? .unavailable }
    private var remaining: Double? {
        status == .current || status == .stale ? snapshot?.window?.remainingPercent : nil
    }
    private var accent: Color { UsageChartStyle.accent(for: remaining, scheme: scheme, selection: usageAccent) }
    private var resetText: String {
        guard remaining != nil, let reset = snapshot?.window?.resetsAt else {
            return status == .expired ? "Reset time passed" : "Weekly limit"
        }
        let seconds = max(0, reset.timeIntervalSince(date))
        if seconds >= 86_400 { return "Resets in about \(Int(ceil(seconds / 86_400)))d" }
        if seconds >= 3_600 { return "Resets in about \(Int(ceil(seconds / 3_600)))h" }
        return "Resets in about \(max(1, Int(ceil(seconds / 60))))m"
    }
}
