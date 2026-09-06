import Charts
import SwiftUI

/// Own scroll-position updates below the chart's content builder so each
/// trackpad event does not rebuild its plots, axes, and hover readout.
struct HistoryChartScrolling: ViewModifier {
    let range: ClosedRange<Date>
    let visibleDuration: TimeInterval?
    @Binding var selectedDate: Date?
    @State private var position: Date

    init(range: ClosedRange<Date>, visibleDuration: TimeInterval?, selectedDate: Binding<Date?>) {
        self.range = range
        self.visibleDuration = visibleDuration
        _selectedDate = selectedDate
        _position = State(initialValue: max(range.lowerBound, range.upperBound.addingTimeInterval(-(visibleDuration ?? 0))))
    }

    func body(content: Content) -> some View {
        Group {
            if let visibleDuration {
                content
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDuration)
                    .chartScrollPosition(x: $position)
                    .onChange(of: position) { _, _ in
                        if selectedDate != nil { selectedDate = nil }
                    }
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
            selectedDate = nil
        }
        .onChange(of: visibleDuration) { _, duration in
            guard let duration else { return }
            let end = max(range.lowerBound, range.upperBound.addingTimeInterval(-duration))
            position = min(max(position, range.lowerBound), end)
            selectedDate = nil
        }
    }
}
