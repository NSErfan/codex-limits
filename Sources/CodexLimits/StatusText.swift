import Foundation

enum StatusText {
    static func title(_ status: PaceStatus) -> String {
        switch status {
        case .slowDown: "Consider slowing down"
        case .onTrack: "On track"
        case .roomToUseMore: "Room to use more"
        }
    }

    static func message(
        forecast: Forecast,
        remainingPercent: Double,
        fetchedAt: Date,
        deadline: Date,
        windowReset: Date,
        safetyBuffer: Double,
        targetName: String? = nil
    ) -> String {
        let target = targetName ?? (deadline == windowReset ? "the scheduled reset" : "the banked reset’s expiry")
        switch forecast.status {
        case .slowDown:
            let timeLeft = deadline.timeIntervalSince(fetchedAt)
            let timeToEmpty = remainingPercent / max(forecast.safetyPercentPerDay, 0.01) * 86_400
            let early = max(timeLeft - timeToEmpty, 0)
            if early > 0 {
                return "With higher usage, your allowance could run out about \(duration(early)) before \(target)."
            }
            if forecast.safetyRemainingAtReset < safetyBuffer {
                return "With higher usage, you may have less than your \(Int(safetyBuffer.rounded()))% reserve left at \(target)."
            }
            return "With higher usage, you may finish close to your \(Int(safetyBuffer.rounded()))% reserve at \(target)."
        case .onTrack:
            return "Expected to have about \(Int(forecast.expectedRemainingAtReset.rounded()))% left at \(target)."
        case .roomToUseMore:
            return "Expected to have about \(Int(forecast.expectedRemainingAtReset.rounded()))% left at \(target). Your reserve is \(Int(safetyBuffer.rounded()))%."
        }
    }

    static func pace(
        recommendedPercentPerDay: Double,
        deadline: Date,
        now: Date,
        targetName: String = "reset"
    ) -> String {
        let timeLeft = max(deadline.timeIntervalSince(now), 0)
        if timeLeft < 3_600 {
            let budget = recommendedPercentPerDay * (timeLeft / 86_400)
            return "Up to \(oneDecimal(budget))% before \(targetName)"
        }
        if timeLeft <= 86_400 {
            return "Up to \(oneDecimal(recommendedPercentPerDay / 24))% an hour"
        }
        return "Up to \(oneDecimal(recommendedPercentPerDay))% a day"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        if seconds >= 86_400 {
            let days = max(Int((seconds / 86_400).rounded()), 1)
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        let hours = max(Int((seconds / 3_600).rounded()), 1)
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }

    static func updated(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3_600 { return "Updated \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return "Updated \(hours) \(hours == 1 ? "hr" : "hrs") ago"
        }
        let days = Int(seconds / 86_400)
        return "Updated \(days) \(days == 1 ? "day" : "days") ago"
    }

    private static func oneDecimal(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(1))
                .locale(Locale(identifier: "en_US"))
        )
    }
}
