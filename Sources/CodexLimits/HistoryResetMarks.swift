import Charts
import SwiftUI

/// Keeps reset markers and their last recorded percentages consistent across charts.
struct HistoryResetMarks: ChartContent {
    let resets: [HistorySeriesBuilder.Reset]
    let accent: Color
    var selectedReset: Date? = nil

    private var annotatedReset: HistorySeriesBuilder.Reset? {
        resets.first { $0.date == selectedReset } ?? resets.last
    }

    var body: some ChartContent {
        ForEach(resets) { reset in
            RuleMark(x: .value("Reset", reset.date))
                .foregroundStyle(accent.opacity(reset.date == selectedReset ? 0.9 : 0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }

        if let reset = annotatedReset {
            PointMark(x: .value("Last reading before reset", reset.before.date),
                      y: .value("Remaining before reset", reset.before.remainingPercent))
                .foregroundStyle(accent)
                .symbolSize(28)
                .annotation(
                    position: reset.before.remainingPercent < 20 ? .top : .bottom,
                    spacing: 6,
                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                ) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                        Text("\(Int(reset.before.remainingPercent.rounded()))%")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .foregroundStyle(accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(accent.opacity(0.2), lineWidth: 0.5) }
                    .fixedSize()
                    .help("Last recorded before reset: \(Int(reset.before.remainingPercent.rounded()))% remaining at \(reset.before.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())). Reset: \(reset.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())).")
                }
                .accessibilityLabel("Last recorded before reset")
                .accessibilityValue("\(Int(reset.before.remainingPercent.rounded())) percent remaining, recorded \(reset.before.date.formatted()). Reset \(reset.date.formatted()).")
        }
    }
}
