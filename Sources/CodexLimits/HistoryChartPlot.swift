import Charts
import CodexWidgetKit
import SwiftUI

/// Shared curve geometry and sampling-gap styling for both app windows.
struct HistoryChartPlot: ChartContent {
    let data: HistoryChartData
    let accent: Color

    var body: some ChartContent { historyContent(accent: accent) }

    static var gapFill: LinearGradient {
        LinearGradient(
            colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    private func historyContent(accent: Color) -> AnyChartContent {
        if #available(macOS 15.0, *) {
            return AnyChartContent(vectorizedHistory(accent: accent))
        }
        return AnyChartContent(legacyHistory(accent: accent))
    }

    @available(macOS 15.0, *)
    @ChartContentBuilder
    private func vectorizedHistory(accent: Color) -> some ChartContent {
        // Batch by style instead of building two marks for every sample.
        // Namespaced series IDs keep sampled and estimated fills separate.
        AreaPlot(
            data.gapArea,
            x: .value("Time", \.date),
            yStart: .value("Zero", \.baseline),
            yEnd: .value("Remaining", \.remainingPercent),
            series: .value("Series", \.seriesID)
        )
        .foregroundStyle(Self.gapFill)
        .interpolationMethod(.linear)

        AreaPlot(
            data.sampledArea,
            x: .value("Time", \.date),
            yStart: .value("Zero", \.baseline),
            yEnd: .value("Remaining", \.remainingPercent),
            series: .value("Series", \.seriesID)
        )
        .foregroundStyle(UsageChartStyle.area(accent))
        .interpolationMethod(.linear)

        LinePlot(
            data.linePoints,
            x: .value("Time", \.date),
            y: .value("Remaining", \.remainingPercent)
        )
        .foregroundStyle(accent)
        .lineStyle(UsageChartStyle.actualStroke)
        .interpolationMethod(.linear)

        if data.linePoints.count == 1, let point = data.linePoints.first {
            PointMark(x: .value("Time", point.date), y: .value("Remaining", point.remainingPercent))
                .foregroundStyle(accent)
                .symbolSize(20)
        }
    }

    @ChartContentBuilder
    private func legacyHistory(accent: Color) -> some ChartContent {
        ForEach(data.series.connectors) { connector in
            ForEach([connector.start, connector.end], id: \.date) { point in
                AreaMark(
                    x: .value("Time", point.date),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Remaining", point.remainingPercent),
                    series: .value("Series", "gap-\(connector.id)")
                )
                .foregroundStyle(Self.gapFill)
                .interpolationMethod(.linear)
                LineMark(
                    x: .value("Time", point.date),
                    y: .value("Remaining", point.remainingPercent),
                    series: .value("Series", "gap-\(connector.id)")
                )
                .foregroundStyle(accent)
                .lineStyle(UsageChartStyle.actualStroke)
                .interpolationMethod(.linear)
            }
        }

        ForEach(data.plotRuns) { run in
            if run.points.count == 1, let point = run.points.first {
                // Connectors already pass through isolated samples. Only a
                // standalone reading needs a dot to remain visible.
                if data.series.connectors.isEmpty {
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(20)
                }
            } else {
                ForEach(run.points, id: \.date) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Remaining", point.remainingPercent),
                        series: .value("Series", "run-\(run.id)")
                    )
                    .foregroundStyle(UsageChartStyle.area(accent))
                    .interpolationMethod(.linear)
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Remaining", point.remainingPercent),
                        series: .value("Series", "run-\(run.id)")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(UsageChartStyle.actualStroke)
                }
            }
        }
    }

}
