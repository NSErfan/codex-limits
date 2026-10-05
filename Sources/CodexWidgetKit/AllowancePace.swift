import Foundation

public enum AllowancePace {
    public static func dailyPercent(
        remainingPercent: Double,
        reservePercent: Double,
        resetsAt: Date,
        date: Date
    ) -> Double? {
        let days = resetsAt.timeIntervalSince(date) / 86_400
        guard remainingPercent.isFinite, (0 ... 100).contains(remainingPercent),
              reservePercent.isFinite, (0 ... 100).contains(reservePercent),
              days.isFinite, days > 0 else { return nil }
        let rate = max(remainingPercent - reservePercent, 0) / days
        return rate.isFinite ? rate : nil
    }
}
