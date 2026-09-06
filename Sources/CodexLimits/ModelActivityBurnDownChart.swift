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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Remaining limit").font(.system(size: 13, weight: .semibold))
                Text("Model activity bands").font(.system(size: 10)).foregroundStyle(.secondary)
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
                ForEach(history.series.resets, id: \.self) { reset in
                    RuleMark(x: .value("Reset", reset))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                if let date = selectedDate {
                    RuleMark(x: .value("Selected", date))
                        .foregroundStyle(Color.primary.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                if let latest = history.series.latestPoint {
                    PointMark(x: .value("Latest", latest.date), y: .value("Remaining", latest.remainingPercent))
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
            .accessibilityLabel("Remaining limit over the selected period")
        }
    }

    @ViewBuilder private var readout: some View {
        let selection = history.selection(at: selectedDate, visibleSpan: viewport.visibleDuration ?? timeline.range.upperBound.timeIntervalSince(timeline.range.lowerBound))
        Group {
            switch selection {
            case let .point(point): Text("\(Int(point.remainingPercent.rounded()))% remaining")
            case let .estimated(point): Text("≈\(Int(point.remainingPercent.rounded()))% · Estimated — no sample here")
            case .reset: Text("Limit reset")
            case nil: Text(history.series.isEmpty ? "No recorded limit readings" : "Observed usage · Muted gaps are estimated")
            }
        }
        .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }
}
