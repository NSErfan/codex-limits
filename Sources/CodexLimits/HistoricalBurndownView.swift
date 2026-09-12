import CodexWidgetKit
import SwiftUI

struct HistoricalBurndownView: View {
    let value: HistoricalForecast
    let safetyBuffer: Double
    var onSelectDate: ((Date) -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            chart(value)
            Text("Recomputed with your current \(safetyBuffer.formatted())% safety buffer and the scheduled reset. Past banked resets and daily token estimates are not included.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chart(_ value: HistoricalForecast) -> some View {
        let accent = UsageChartStyle.accent(for: value.window.remainingPercent, scheme: colorScheme, selection: usageAccent)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(value.date.timeIntervalSince(value.lastReading.observedAt) >= 60 ? "≈" : "")\(Int(value.window.remainingPercent.rounded()))% remaining")
                    .font(.system(size: 22, weight: .medium, design: .rounded))
                Spacer()
                Text(value.assumedDuration ? "Assumed window" : "Recorded window")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Last reading: \(value.lastReading.observedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption).foregroundStyle(.secondary)
            if value.date.timeIntervalSince(value.lastReading.observedAt) >= 60 {
                Text("No sample at this time. Uses the last recorded balance; usage since that reading is unknown.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            BurnDownChart(window: value.window, samples: value.samples, tokenHistory: [], fetchedAt: value.date,
                          forecast: value.forecast, safetyBuffer: safetyBuffer, resetCredits: [],
                          paceDeadline: value.window.resetsAt, paceTargetCreditID: .constant(""), isHistorical: true, onSelectDate: onSelectDate)
            HStack {
                Text("Reset").foregroundStyle(.secondary)
                Spacer()
                Text(value.window.resetsAt.formatted(date: .abbreviated, time: .shortened))
            }
            HStack {
                Text("Suggested pace").foregroundStyle(.secondary)
                Spacer()
                Text(StatusText.pace(recommendedPercentPerDay: value.forecast.recommendedPercentPerDay,
                                     deadline: value.window.resetsAt, now: value.date))
            }
            .foregroundStyle(accent)
        }
        .font(.system(size: 12))
    }

}
