import Foundation

struct BurndownTarget: Codable, Hashable {
    let date: Date
    private let windowReset: Date
    private let durationMinutes: Int?

    init?(date: Date, window: UsageWindow, now: Date) {
        guard Self.accepts(date, in: window, now: now) else { return nil }
        self.date = date
        windowReset = window.resetsAt
        durationMinutes = window.durationMinutes
    }

    static func accepts(_ date: Date, in window: UsageWindow, now: Date) -> Bool {
        date > now && date > window.startsAt && date <= window.resetsAt
    }

    func isValid(in window: UsageWindow, now: Date) -> Bool {
        UsageWindow.hasSameReset(windowReset, window.resetsAt)
            && (durationMinutes == nil || durationMinutes == window.durationMinutes)
            && Self.accepts(date, in: window, now: now)
    }
}
