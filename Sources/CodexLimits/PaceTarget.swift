import Foundation

struct PaceTarget {
    let startsAt: Date
    let deadline: Date
    let reservePercent: Double

    func remainingPercent(at date: Date) -> Double {
        let span = deadline.timeIntervalSince(startsAt)
        guard span > 0 else { return reservePercent }
        let elapsed = min(max(date.timeIntervalSince(startsAt) / span, 0), 1)
        return 100 - (100 - reservePercent) * elapsed
    }
}
