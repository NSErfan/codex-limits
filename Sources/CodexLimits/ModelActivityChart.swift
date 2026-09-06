import Charts
import SwiftUI

struct ModelActivityChart: View {
    let timeline: ModelActivityTimeline
    let visibleTimeline: ModelActivityTimeline
    let viewport: ModelActivityViewport
    @Environment(\.colorScheme) private var colorScheme
    @Binding var selectedDate: Date?

    var body: some View {
        Chart {
            ForEach(timeline.modelSegments) { segment in
                RectangleMark(xStart: .value("Start", segment.start), xEnd: .value("End", segment.end),
                              yStart: .value("Tokens", Double(segment.lower)), yEnd: .value("Tokens", Double(segment.upper)))
                    .foregroundStyle(ModelActivityColors.model(segment.model, scheme: colorScheme))
                    .accessibilityLabel(segment.model)
                    .accessibilityValue("\(segment.upper - segment.lower) tokens")
            }
            if let date = selectedDate {
                RuleMark(x: .value("Selected", date))
                    .foregroundStyle(Color.primary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: timeline.range)
        .chartYScale(domain: 0 ... max(1, Double(timeline.intervals.map(\.matched).max() ?? 0) * 1.1))
        .modifier(ModelActivitySelection(timeline: timeline, viewport: viewport, selectedDate: $selectedDate))
        .modifier(ModelActivityScrolling(viewport: viewport, selectedDate: $selectedDate))
        .chartLegend(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.06))
                AxisValueLabel {
                    if let tokens = value.as(Double.self) {
                        Text(tokens, format: .number.notation(.compactName)).frame(width: 35, alignment: .trailing)
                    }
                }
            }
        }
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Model activity timeline")
        .accessibilityValue("\(visibleTimeline.matchingIntervals) matching intervals out of \(visibleTimeline.activeIntervals) active intervals")
        .accessibilityAdjustableAction { direction in
            let current = visibleTimeline.interval(at: selectedDate)
            let index = visibleTimeline.intervals.firstIndex { $0.id == current?.id } ?? 0
            let next: Int
            switch direction {
            case .increment: next = min(index + 1, visibleTimeline.intervals.count - 1)
            case .decrement: next = max(index - 1, 0)
            @unknown default: return
            }
            let interval = visibleTimeline.intervals[next]
            selectedDate = interval.start.addingTimeInterval(interval.end.timeIntervalSince(interval.start) / 2)
        }
    }

}
