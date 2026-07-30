import Foundation

struct BurnPoint: Equatable, Identifiable, Sendable {
    let date: Date
    let remaining: Double

    var id: Date { date }
}

enum ChartInteraction {
    static let hoverToleranceFraction = 0.015

    static func nearest<Item>(
        to target: Date,
        in items: [Item],
        date: (Item) -> Date
    ) -> Item? {
        items.min {
            abs(date($0).timeIntervalSince(target)) < abs(date($1).timeIntervalSince(target))
        }
    }

    static func nearest<Item>(
        to target: Date,
        in items: [Item],
        visibleSpan: TimeInterval,
        date: (Item) -> Date
    ) -> Item? {
        nearest(to: target, in: items, date: date).flatMap {
            abs(date($0).timeIntervalSince(target)) <= visibleSpan * hoverToleranceFraction
                ? $0
                : nil
        }
    }
}

enum WindowChartSeries {
    static func observed(
        window: UsageWindow,
        samples: [UsageSample],
        tokenHistory: [TokenDay],
        fetchedAt: Date
    ) -> [BurnPoint] {
        let current = BurnPoint(date: fetchedAt, remaining: window.remainingPercent)
        let local = samples
            .filter { $0.observedAt > window.startsAt && $0.observedAt < fetchedAt }
            .map { BurnPoint(date: $0.observedAt, remaining: $0.remainingPercent) }
            .sorted { $0.date < $1.date }
        let firstKnown = local.first ?? current
        let buckets = tokenHistory
            .filter {
                $0.date.addingTimeInterval(86_400) > window.startsAt && $0.date < firstKnown.date
            }
            .sorted { $0.date < $1.date }
        let totalTokens = buckets.reduce(Int64(0)) { $0 + $1.tokens }
        var bootstrapped: [BurnPoint] = []

        if totalTokens > 0 {
            var cumulativeTokens: Int64 = 0
            for bucket in buckets {
                cumulativeTokens += bucket.tokens
                let date = min(
                    max(bucket.date.addingTimeInterval(86_400), window.startsAt),
                    firstKnown.date
                )
                let used = (100 - firstKnown.remaining) * Double(cumulativeTokens) / Double(totalTokens)
                bootstrapped.append(BurnPoint(date: date, remaining: 100 - used))
            }
        }

        // Daily token buckets seed the curve until percentage samples cover the window.
        return deduplicated(
            [BurnPoint(date: window.startsAt, remaining: 100)] + bootstrapped + local + [current]
        )
    }

    static func projection(
        window: UsageWindow,
        fetchedAt: Date,
        deadline: Date,
        rate: Double,
        remainingAtDeadline: Double
    ) -> [BurnPoint] {
        let current = BurnPoint(date: fetchedAt, remaining: window.remainingPercent)
        guard rate > 0 else {
            return [current, BurnPoint(date: deadline, remaining: window.remainingPercent)]
        }
        let exhaustion = fetchedAt.addingTimeInterval(window.remainingPercent / rate * 86_400)
        let endpoint = exhaustion < deadline
            ? BurnPoint(date: exhaustion, remaining: 0)
            : BurnPoint(date: deadline, remaining: remainingAtDeadline)
        return [current, endpoint]
    }

    static func visibleCredits(_ credits: [ResetCredit], window: UsageWindow) -> [ResetCredit] {
        credits.filter { credit in
            guard let expiresAt = credit.expiresAt else { return false }
            return expiresAt > window.startsAt && expiresAt < window.resetsAt
        }
    }

    private static func deduplicated(_ points: [BurnPoint]) -> [BurnPoint] {
        points.sorted { $0.date < $1.date }.reduce(into: []) { result, point in
            if result.last?.date == point.date {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
    }
}

enum BankedResetPresentation {
    static func qualifies(_ credit: ResetCredit, now: Date, windowReset: Date) -> Bool {
        credit.expiresAt.map { $0 > now && $0 < windowReset } == true
    }

    static func labelParts(for credits: [ResetCredit]) -> (head: String, extra: String?) {
        let head = credits.compactMap(\.expiresAt).min().map { dateText($0) } ?? "No expiry"
        let extraCount = credits.count - 1
        return (head, extraCount > 0 ? "+\(extraCount) more" : nil)
    }

    static func itemText(_ credit: ResetCredit, windowReset: Date?) -> String {
        let title = credit.title ?? "Banked reset"
        guard let expiresAt = credit.expiresAt else { return "\(title) · no expiry" }
        let suffix = windowReset.map { expiresAt >= $0 ? " · after the next reset" : "" } ?? ""
        return "\(title) · expires \(dateText(expiresAt))\(suffix)"
    }

    static func hint(hasSelection: Bool) -> String {
        hasSelection
            ? "Pick the checked reset again to pace to the window reset."
            : "Pick a banked reset to pace toward its expiry."
    }

    static func dateText(_ date: Date?) -> String {
        guard let date else { return "no expiry" }
        return date.formatted(
            .dateTime.month(.abbreviated).day().hour().minute()
                .locale(Locale(identifier: "en_US"))
        )
    }
}

enum StatusText {
    static func title(_ status: PaceStatus) -> String {
        switch status {
        case .slowDown: "Slow down"
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
        safetyBuffer: Double
    ) -> String {
        let target = deadline == windowReset ? "reset" : "banked reset expiry"
        switch forecast.status {
        case .slowDown:
            let timeLeft = deadline.timeIntervalSince(fetchedAt)
            let timeToEmpty = remainingPercent / max(forecast.safetyPercentPerDay, 0.01) * 86_400
            let early = max(timeLeft - timeToEmpty, 0)
            return early > 0
                ? "At this pace, your limit may run out \(duration(early)) before the \(target)."
                : "Your current pace is too close to the limit."
        case .onTrack:
            return "You’re on track to have \(Int(forecast.expectedRemainingAtReset.rounded()))% left at the \(target)."
        case .roomToUseMore:
            let room = max(forecast.expectedRemainingAtReset - safetyBuffer, 0)
            return "You can use about \(Int(room.rounded()))% more before the \(target)."
        }
    }

    static func pace(recommendedPercentPerDay: Double, deadline: Date, now: Date) -> String {
        if deadline.timeIntervalSince(now) <= 86_400 {
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
