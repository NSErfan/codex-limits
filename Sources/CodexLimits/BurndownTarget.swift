import Foundation

struct BurndownTarget: Hashable {
    let date: Date
    private let windowReset: Date

    init?(date: Date, window: UsageWindow, now: Date) {
        guard Self.accepts(date, in: window, now: now) else { return nil }
        self.date = date
        windowReset = window.resetsAt
    }

    static func accepts(_ date: Date, in window: UsageWindow, now: Date) -> Bool {
        date > now && date > window.startsAt && date <= window.resetsAt
    }

    func isValid(in window: UsageWindow, now: Date) -> Bool {
        UsageWindow.hasSameReset(windowReset, window.resetsAt)
            && Self.accepts(date, in: window, now: now)
    }
}
