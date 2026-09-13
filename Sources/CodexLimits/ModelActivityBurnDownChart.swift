import Charts
import CodexWidgetKit
import SwiftUI

struct ModelActivityBurnDownChart: View {
    let history: HistoryChartData
    let timeline: ModelActivityTimeline
    let viewport: ModelActivityViewport
    @Environment(\.colorScheme) private var colorScheme
    let accent: Color
    @Binding var selectedDate: Date?

    private var selection: HistoryChartData.Selection? {
        history.selection(at: selectedDate, visibleSpan: viewport.visibleDuration ?? timeline.range.upperBound.timeIntervalSince(timeline.range.lowerBound))
    }

    var body: some View {
        let hoveredReset: Date? = if case let .reset(reset) = selection { reset.date } else { nil }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Remaining allowance").font(.system(size: 13, weight: .semibold))
                Text("Activity by model").font(.system(size: 10)).foregroundStyle(.secondary)
                ModelActivityRangeNavigation(viewport: viewport, selectedDate: $selectedDate)
                Spacer()
                readout
            }
            Chart {
                ForEach(timeline.modelSegments) { segment in
                    let laneHeight = 10.0 / Double(max(timeline.matchedModels.count, 1))
                    RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                                  yStart: .value("Activity band", -12 + Double(segment.lane) * laneHeight),
                                  yEnd: .value("Activity band", -12 + Double(segment.lane + 1) * laneHeight))
                        .foregroundStyle(ModelActivityColors.model(segment.model, scheme: colorScheme))
                        .accessibilityLabel("\(segment.model) activity")
                        .accessibilityValue("\(segment.start.formatted()) to \(segment.end.formatted())")
                }
                HistoryChartPlot(data: history, accent: accent)
                HistoryResetMarks(resets: history.series.resets, accent: accent, selectedReset: hoveredReset)
                if let date = selectedDate {
                    RuleMark(x: .value("Selected", date))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let latest = history.series.latestPoint {
                    PointMark(x: .value("Latest", latest.date), y: .value("Remaining allowance", latest.remainingPercent))
                        .foregroundStyle(accent).symbolSize(20)
                }
            }
            .chartXScale(domain: timeline.range)
            .chartYScale(domain: -12 ... 100)
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text("\(Int(percent))%").frame(width: 35, alignment: .trailing)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .modifier(ModelActivitySelection(timeline: timeline, viewport: viewport, selectedDate: $selectedDate))
            .modifier(ModelActivityScrolling(viewport: viewport, selectedDate: $selectedDate))
            .frame(height: 150)
            .accessibilityLabel("Remaining allowance over the selected period")
        }
    }

    @ViewBuilder private var readout: some View {
        Group {
            switch selection {
            case let .point(point): Text("\(Int(point.remainingPercent.rounded()))% remaining")
            case let .estimated(point): Text("About \(Int(point.remainingPercent.rounded()))% remaining · Estimated between readings")
            case let .reset(reset):
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last reading before reset: \(Int(reset.before.remainingPercent.rounded()))% · Reset \(reset.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                    Text("Recorded \(reset.before.date.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                        .font(.system(size: 10))
                }
            case nil:
                Text(history.series.isEmpty ? "No allowance readings recorded." : "Recorded allowance · Shaded gaps are estimated")
            }
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
        .frame(height: 28, alignment: .trailing)
    }
}
