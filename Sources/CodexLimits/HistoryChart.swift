import Charts
import CodexWidgetKit
import SwiftUI

struct HistoryChart: View {
    let range: ClosedRange<Date>
    let visibleDuration: TimeInterval?
    let remainingPercent: Double

    private let data: HistoryChartData
    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    private var accent: Color { UsageChartStyle.accent(for: remainingPercent, scheme: colorScheme, selection: usageAccent) }

    private var gapFill: LinearGradient {
        LinearGradient(
            colors: [Color.secondary.opacity(0.12), Color.secondary.opacity(0.02)],
            startPoint: .top, endPoint: .bottom
        )
    }

    init(
        samples: [UsageSample],
        range: ClosedRange<Date>,
        bucketDuration: TimeInterval,
        visibleDuration: TimeInterval?,
        remainingPercent: Double
    ) {
        self.range = range
        self.visibleDuration = visibleDuration
        self.remainingPercent = remainingPercent
        data = HistoryChartData(samples: samples, range: range, bucketDuration: bucketDuration)
    }

    private var axisDayStride: Int { visibleDuration == nil ? 5 : 1 }

    var body: some View {
        let selection = data.selection(
            at: selectedDate,
            visibleSpan: visibleDuration ?? range.upperBound.timeIntervalSince(range.lowerBound)
        )
        VStack(alignment: .leading, spacing: 3) {
            readout(selection: selection)
            if data.series.isEmpty {
                Text("No history yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                chart(selection: selection)
                    .modifier(HistoryChartScrolling(
                        range: range, visibleDuration: visibleDuration, selectedDate: $selectedDate
                    ))
            }
        }
    }

    private func readout(selection: HistoryChartData.Selection?) -> some View {
        Group {
            if case let .reset(date) = selection {
                ChartHoverReadout(
                    title: "Reset", detail: date.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                    symbol: "arrow.counterclockwise"
                )
            } else if case let .estimated(point) = selection {
                ChartHoverReadout(
                    title: "≈\(Int(point.remainingPercent.rounded()))% remaining",
                    detail: point.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                    hint: "Estimated · No sample here"
                )
            } else if case let .point(point) = selection {
                ChartHoverReadout(
                    title: "\(Int(point.remainingPercent.rounded()))% remaining",
                    detail: point.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                )
            } else {
                HStack {
                    ChartLegendItem(label: "Remaining", color: accent)
                    Spacer()
                    if !data.series.connectors.isEmpty {
                        HStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(gapFill)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 2)
                                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                                }
                                .frame(width: 12, height: 8)
                            Text("No samples")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(height: 40)
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
        .foregroundStyle(gapFill)
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
                .foregroundStyle(gapFill)
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

    private func chart(selection: HistoryChartData.Selection?) -> some View {
        let accent = self.accent
        let hoveredReset: Date? = if case let .reset(date) = selection { date } else { nil }
        let hoveredPoint: HistorySeriesBuilder.Point? = switch selection {
        case let .point(point), let .estimated(point): point
        default: nil
        }
        return Chart {
            historyContent(accent: accent)

            ForEach(data.series.resets, id: \.self) { resetDate in
                RuleMark(x: .value("Reset", resetDate))
                    .foregroundStyle(accent.opacity(resetDate == hoveredReset ? 0.9 : 0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if hoveredReset == nil, let hovered = hoveredPoint {
                RuleMark(x: .value("Hovered", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(
                    x: .value("Hovered", hovered.date),
                    y: .value("Remaining", hovered.remainingPercent)
                )
                .foregroundStyle(accent)
                .symbolSize(55)
            }

            if let latest = data.series.latestPoint {
                PointMark(x: .value("Latest", latest.date), y: .value("Remaining", latest.remainingPercent))
                    .foregroundStyle(accent.opacity(0.15))
                    .symbolSize(190)
                PointMark(x: .value("Latest", latest.date), y: .value("Remaining", latest.remainingPercent))
                    .foregroundStyle(accent)
                    .symbolSize(35)
            }
        }
        .chartXSelection(value: $selectedDate)
        .onTapGesture {
            // A click pins the chart selection on macOS; release it so the
            // readout follows the pointer again instead of freezing.
            DispatchQueue.main.async { selectedDate = nil }
        }
        .onContinuousHover { phase in
            // chartXSelection does not reliably clear when the pointer
            // leaves the plot, which froze the readout in place.
            if case .ended = phase { selectedDate = nil }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: 0 ... 100, range: .plotDimension(padding: 6))
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisDayStride)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                    }
                }
                .font(UsageChartStyle.axisFont)
                .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                AxisGridLine(stroke: UsageChartStyle.gridStroke)
                    .foregroundStyle(UsageChartStyle.grid)
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
                .font(UsageChartStyle.axisFont)
                .foregroundStyle(Color.secondary)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 200)
        .padding(.top, 4)
        .accessibilityLabel("Usage history")
        .accessibilityValue(
            data.series.accessibilitySummary(
                days: Int(range.upperBound.timeIntervalSince(range.lowerBound) / 86_400)
            )
        )
    }
}
