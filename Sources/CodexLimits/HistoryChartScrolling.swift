import Charts
import SwiftUI

/// Own scroll-position updates below the chart's content builder so each
/// trackpad event does not rebuild its plots, axes, and hover readout.
struct HistoryChartScrolling: ViewModifier {
    let range: ClosedRange<Date>
    let visibleDuration: TimeInterval?
    let interaction: HistoryChartInteraction
    @State private var position: Date

    init(range: ClosedRange<Date>, visibleDuration: TimeInterval?, interaction: HistoryChartInteraction) {
        self.range = range
        self.visibleDuration = visibleDuration
        self.interaction = interaction
        _position = State(initialValue: max(range.lowerBound, range.upperBound.addingTimeInterval(-(visibleDuration ?? 0))))
    }

    func body(content: Content) -> some View {
        Group {
            if let visibleDuration {
                content
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDuration)
                    .chartScrollPosition(x: Binding(
                        get: { position },
                        set: { updated in
                            guard updated != position else { return }
                            interaction.scroll()
                            position = updated
                        }
                    ))
            } else {
                content
            }
        }
        .onChange(of: range) { previous, updated in
            guard let visibleDuration else { return }
            let previousEnd = previous.upperBound.addingTimeInterval(-visibleDuration)
            let updatedEnd = max(updated.lowerBound, updated.upperBound.addingTimeInterval(-visibleDuration))
            if abs(position.timeIntervalSince(previousEnd)) < 1 {
                position = updatedEnd
            } else {
                position = min(max(position, updated.lowerBound), updatedEnd)
            }
            interaction.select(nil)
        }
        .onChange(of: visibleDuration) { _, duration in
            guard let duration else { return }
            let end = max(range.lowerBound, range.upperBound.addingTimeInterval(-duration))
            position = min(max(position, range.lowerBound), end)
            interaction.select(nil)
        }
    }
}
