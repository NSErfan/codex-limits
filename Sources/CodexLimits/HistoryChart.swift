import Charts
import CodexWidgetKit
import SwiftUI

struct HistoryChart: View {
    let samples: [UsageSample]
    let range: ClosedRange<Date>
    let bucketDuration: TimeInterval
    let visibleDuration: TimeInterval?
    let remainingPercent: Double

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

    private var series: HistorySeriesBuilder.Series {
        HistorySeriesBuilder.series(from: samples, in: range, bucketDuration: bucketDuration)
    }

    private var axisDayStride: Int {
        visibleDuration == nil ? 5 : 1
    }

    private var hoveredPoint: HistorySeriesBuilder.Point? {
        guard let selectedDate, hoveredGap == nil else { return nil }
        return ChartInteraction.nearest(
            to: selectedDate,
            in: series.runs.flatMap(\.points),
            date: \.date
        )
    }

    private var hoveredGap: HistorySeriesBuilder.Connector? {
        guard let selectedDate else { return nil }
        return series.connectors.first { selectedDate > $0.start.date && selectedDate < $0.end.date }
    }

    private var hoveredReset: Date? {
        guard let selectedDate else { return nil }
        return ChartInteraction.nearest(
            to: selectedDate,
            in: series.resets,
            visibleSpan: visibleDuration ?? range.upperBound.timeIntervalSince(range.lowerBound),
            date: { $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            readout
            if series.isEmpty {
                Text("No history yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else if let visibleDuration {
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDuration)
                    .chartScrollPosition(
                        initialX: range.upperBound.addingTimeInterval(-visibleDuration)
                    )
            } else {
                chart
            }
        }
    }

    private var readout: some View {
        HStack(spacing: 4) {
            ChartLegendItem(label: "Remaining", color: accent)
            Spacer()
            if let hoveredReset {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8))
                    .foregroundStyle(accent)
                Text("Reset")
                    .foregroundStyle(accent)
                Text(
                    hoveredReset,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .foregroundStyle(.secondary)
            } else if hoveredGap != nil {
                Text("No samples · estimated connection")
                    .foregroundStyle(.secondary)
            } else if let hovered = hoveredPoint {
                Text("\(Int(hovered.remainingPercent.rounded()))%")
                    .fontWeight(.semibold)
                Text(
                    hovered.date,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .foregroundStyle(.secondary)
            } else if !series.connectors.isEmpty {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(gapFill)
                        .overlay {
                            RoundedRectangle(cornerRadius: 2)
                                .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        }
                        .frame(width: 12, height: 8)
                    Text("No samples")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(UsageChartStyle.axisFont)
        .monospacedDigit()
        .frame(height: 12)
    }

    private var chart: some View {
        let accent = self.accent
        return Chart {
            ForEach(series.connectors) { connector in
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

            ForEach(series.runs) { run in
                if run.points.count == 1, let point = run.points.first {
                    // Connectors already pass through isolated samples. Only a
                    // standalone reading needs a dot to remain visible.
                    if series.connectors.isEmpty {
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

            ForEach(series.resets, id: \.self) { resetDate in
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

            if let latest = series.latestPoint {
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
            series.accessibilitySummary(
                days: Int(range.upperBound.timeIntervalSince(range.lowerBound) / 86_400)
            )
        )
    }
}
