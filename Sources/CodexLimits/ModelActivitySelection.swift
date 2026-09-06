import Charts
import SwiftUI

/// Use Charts' native selection so its scroll view also receives trackpad input.
struct ModelActivitySelection: ViewModifier {
    let timeline: ModelActivityTimeline
    let viewport: ModelActivityViewport
    @Binding var selectedDate: Date?

    func body(content: Content) -> some View {
        content
            .chartXSelection(value: Binding<Date?>(
                get: { selectedDate },
                set: { date in
                    guard !viewport.isScrolling, let date, let interval = timeline.interval(at: date) else {
                        selectedDate = nil
                        return
                    }
                    let start = max(interval.start, viewport.visibleRange.lowerBound)
                    let end = min(interval.end, viewport.visibleRange.upperBound)
                    guard start < end else { selectedDate = nil; return }
                    let midpoint = start.addingTimeInterval(end.timeIntervalSince(start) / 2)
                    if selectedDate != midpoint { selectedDate = midpoint }
                }
            ))
            .onContinuousHover { phase in
                if case .ended = phase { selectedDate = nil }
            }
            .onTapGesture {
                // Release native click-pinning, as in the menu's history chart.
                DispatchQueue.main.async { selectedDate = nil }
            }
    }
}
