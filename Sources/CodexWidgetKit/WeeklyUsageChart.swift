import Charts
import SwiftUI

struct WeeklyUsageChart: View {
    let snapshot: WeeklyWidgetSnapshot
    let accent: Color

    var body: some View {
        if let window = snapshot.window {
            Chart {
                RuleMark(y: .value("Half remaining", 50))
                    .foregroundStyle(UsageChartStyle.grid)
                    .lineStyle(UsageChartStyle.gridStroke)
                ForEach([window.startsAt, window.resetsAt], id: \.self) { date in
                    LineMark(
                        x: .value("Date", date),
                        y: .value("Even pace", date == window.startsAt ? 100 : 0),
                        series: .value("Series", "Even pace")
                    )
                    .foregroundStyle(UsageChartStyle.guide)
                    .lineStyle(UsageChartStyle.guideStroke)
                }
                ForEach(snapshot.samples, id: \.date) { sample in
                    AreaMark(
                        x: .value("Date", sample.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Remaining allowance", sample.remainingPercent)
                    )
                    .foregroundStyle(UsageChartStyle.area(accent))
                    .interpolationMethod(.linear)
                    LineMark(
                        x: .value("Date", sample.date),
                        y: .value("Remaining allowance", sample.remainingPercent),
                        series: .value("Series", "Usage so far")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(UsageChartStyle.actualStroke)
                    .interpolationMethod(.linear)
                }
                PointMark(x: .value("Latest", snapshot.fetchedAt), y: .value("Remaining allowance", window.remainingPercent))
                    .foregroundStyle(accent.opacity(0.15))
                    .symbolSize(150)
                PointMark(x: .value("Latest", snapshot.fetchedAt), y: .value("Remaining allowance", window.remainingPercent))
                    .foregroundStyle(accent)
                    .symbolSize(25)
            }
            .chartXScale(domain: window.startsAt ... window.resetsAt)
            .chartYScale(domain: 0 ... 100)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .accessibilityLabel("Weekly remaining allowance, with \(snapshot.samples.count) readings. The dashed line shows an even pace from 100 percent at the start to zero at the scheduled reset.")
        }
    }
}
