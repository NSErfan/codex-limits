import Charts
import SwiftUI

struct WeeklyUsageChart: View {
    let snapshot: WeeklyWidgetSnapshot
    let accent: Color

    var body: some View {
        if let window = snapshot.window {
            Chart {
                RuleMark(y: .value("Half remaining", 50))
                    .foregroundStyle(Color.primary.opacity(0.07))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                ForEach([window.startsAt, window.resetsAt], id: \.self) { date in
                    LineMark(
                        x: .value("Date", date),
                        y: .value("Even pace", date == window.startsAt ? 100 : 0),
                        series: .value("Series", "Even pace")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
                ForEach(snapshot.samples, id: \.date) { sample in
                    AreaMark(
                        x: .value("Date", sample.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Remaining", sample.remainingPercent)
                    )
                    .foregroundStyle(LinearGradient(
                        colors: [accent.opacity(0.23), accent.opacity(0.01)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .interpolationMethod(.linear)
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Remaining", sample.remainingPercent),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .interpolationMethod(.linear)
                }
                PointMark(x: .value("Latest", snapshot.fetchedAt), y: .value("Remaining", window.remainingPercent))
                    .foregroundStyle(accent.opacity(0.15))
                    .symbolSize(150)
                PointMark(x: .value("Latest", snapshot.fetchedAt), y: .value("Remaining", window.remainingPercent))
                    .foregroundStyle(accent)
                    .symbolSize(25)
            }
            .chartXScale(domain: window.startsAt ... window.resetsAt)
            .chartYScale(domain: 0 ... 100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityLabel("Weekly remaining usage, \(snapshot.samples.count) readings. Dashed line shows an even pace from 100 to zero percent at reset.")
        }
    }
}
