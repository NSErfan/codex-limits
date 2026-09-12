import Combine
import Foundation

@MainActor
final class HistoryChartInteraction: ObservableObject {
    @Published private(set) var selectedDate: Date?
    private var lastScrollTime = -TimeInterval.infinity

    func select(_ date: Date?, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        // Native pointer tracking can reselect a date as the plot moves beneath
        // the pointer. Keep that from rebuilding the chart during a scroll.
        guard date == nil || time - lastScrollTime >= 0.15 else { return }
        if selectedDate != date { selectedDate = date }
    }

    func scroll(at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        lastScrollTime = time
        select(nil, at: time)
    }
}
