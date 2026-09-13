import Foundation

enum ForecastEngine {
    /// The date pacing aims at: the selected banked reset's expiry while it
    /// still falls inside the window, the window reset otherwise.
    static func paceDeadline(
        window: UsageWindow,
        resetCredits: [ResetCredit],
        now: Date,
        selectedCreditID: String?
    ) -> Date {
        guard let selectedCreditID, !selectedCreditID.isEmpty,
              let expiry = resetCredits.first(where: { $0.id == selectedCreditID })?.expiresAt,
              expiry > now, expiry < window.resetsAt else {
            return window.resetsAt
        }
        return expiry
    }

    static func evaluate(
        window: UsageWindow,
        samples: [UsageSample],
        tokenHistory: [TokenDay],
        safetyBuffer: Double,
        now: Date,
        previousStatus: PaceStatus?,
        deadline: Date? = nil
    ) -> Forecast {
        let target = deadline ?? window.resetsAt
        let daysLeft = max(target.timeIntervalSince(now) / 86_400, 0)
        let currentSamples = samples
            .filter {
                UsageWindow.hasSameReset($0.resetsAt, window.resetsAt) && $0.observedAt <= now
            }
            .sorted { $0.observedAt < $1.observedAt }
        let elapsedDays = max(now.timeIntervalSince(window.startsAt) / 86_400, 1 / 24)
        let windowRate = max((100 - window.remainingPercent) / elapsedDays, 0)
        let recentRate = recentRate(
            window: window,
            samples: currentSamples,
            now: now,
            fallback: windowRate
        )

        let currentRate = currentSamples.count > 1
            ? 0.7 * recentRate + 0.3 * windowRate
            : windowRate
        let historicalRates = resetGroups(
            samples.filter { !UsageWindow.hasSameReset($0.resetsAt, window.resetsAt) }
        ).compactMap { windowSamples -> Double? in
            let ordered = windowSamples.sorted { $0.observedAt < $1.observedAt }
            guard let first = ordered.first,
                  let last = ordered.last,
                  last.observedAt > first.observedAt else { return nil }
            // Spread the drop over at least a day: sampling clusters around
            // active use, and dividing a burst by its own few hours would
            // pass it off as a sustained daily pace.
            let days = max(last.observedAt.timeIntervalSince(first.observedAt) / 86_400, 1)
            return max((first.remainingPercent - last.remainingPercent) / days, 0)
        }
        let historicalRate: Double
        if historicalRates.isEmpty {
            historicalRate = tokenBootstrapRate(
                window: window,
                windowRate: windowRate,
                tokenHistory: tokenHistory,
                now: now
            ) ?? currentRate
        } else {
            historicalRate = historicalRates.reduce(0, +) / Double(historicalRates.count)
        }
        let expectedRate = 0.75 * currentRate + 0.25 * historicalRate
        let safetyRate = max(currentRate, historicalRate) * 1.2
        let expected = max(window.remainingPercent - expectedRate * daysLeft, 0)
        let safety = max(window.remainingPercent - safetyRate * daysLeft, 0)
        let historical = max(window.remainingPercent - historicalRate * daysLeft, 0)
        let recommended = daysLeft > 0
            ? max(window.remainingPercent - safetyBuffer, 0) / daysLeft
            : 0
        // Being at or above the target line means the pace so far is fine,
        // whatever past windows looked like; a projection built from history
        // must not raise the alarm on its own.
        let paceTarget = PaceTarget(startsAt: window.startsAt, deadline: target, reservePercent: safetyBuffer)
        let aheadOfTarget = window.remainingPercent >= paceTarget.remainingPercent(at: now)

        let status: PaceStatus
        if !aheadOfTarget,
           safety < safetyBuffer || (previousStatus == .slowDown && safety < safetyBuffer + 1) {
            status = .slowDown
        } else if expected > 8 || (previousStatus == .roomToUseMore && expected > 7) {
            status = .roomToUseMore
        } else {
            status = .onTrack
        }

        return Forecast(
            status: status,
            expectedRemainingAtReset: expected,
            safetyRemainingAtReset: safety,
            historicalRemainingAtReset: historical,
            recommendedPercentPerDay: recommended,
            currentPercentPerDay: expectedRate,
            historicalPercentPerDay: historicalRate,
            safetyPercentPerDay: safetyRate
        )
    }

    private static func recentRate(
        window: UsageWindow,
        samples: [UsageSample],
        now: Date,
        fallback: Double
    ) -> Double {
        let trailingStart = max(window.startsAt, now.addingTimeInterval(-86_400))
        let baseline: (date: Date, remaining: Double)

        if trailingStart == window.startsAt {
            // The reset is a known 100% point. On a fresh window it is the
            // only honest baseline when local samples cover just a short
            // burst near now.
            baseline = (window.startsAt, 100)
        } else if let nearest = samples.min(by: {
            abs($0.observedAt.timeIntervalSince(trailingStart))
                < abs($1.observedAt.timeIntervalSince(trailingStart))
        }), now.timeIntervalSince(nearest.observedAt) >= 12 * 3_600 {
            baseline = (nearest.observedAt, nearest.remainingPercent)
        } else {
            // Without meaningful trailing-day coverage, a clustered sample
            // burst is not enough evidence for a sustained daily pace.
            return fallback
        }

        let elapsed = now.timeIntervalSince(baseline.date)
        guard elapsed > 0 else { return fallback }
        let days = elapsed / 86_400
        return max((baseline.remaining - window.remainingPercent) / days, 0)
    }

    private static func resetGroups(_ samples: [UsageSample]) -> [[UsageSample]] {
        samples.sorted { $0.resetsAt < $1.resetsAt }.reduce(into: []) { groups, sample in
            if let index = groups.indices.last,
               let reset = groups[index].first?.resetsAt,
               UsageWindow.hasSameReset(sample.resetsAt, reset) {
                groups[index].append(sample)
            } else {
                groups.append([sample])
            }
        }
    }

    private static func tokenBootstrapRate(
        window: UsageWindow,
        windowRate: Double,
        tokenHistory: [TokenDay],
        now: Date
    ) -> Double? {
        let day: TimeInterval = 86_400
        let dayNumber: (Date) -> Int = { Int(floor($0.timeIntervalSince1970 / day)) }
        let start = dayNumber(window.startsAt)
        let today = dayNumber(now)
        let buckets = Dictionary(grouping: tokenHistory, by: { dayNumber($0.date) })
            .mapValues { $0.reduce(Int64(0)) { $0 + $1.tokens } }
        guard let first = buckets.keys.min(),
              let latest = buckets.keys.filter({ $0 < today }).max(),
              latest >= start else { return nil }

        let currentCount = latest - start + 1
        let currentTokens = (start ... latest).reduce(Int64(0)) { $0 + (buckets[$1] ?? 0) }
        let historyEnd = start - 1
        let historyStart = max(first, historyEnd - 27)
        guard historyStart <= historyEnd, currentTokens > 0 else { return nil }

        let historyCount = historyEnd - historyStart + 1
        let historyTokens = (historyStart ... historyEnd).reduce(Int64(0)) { $0 + (buckets[$1] ?? 0) }
        let currentAverage = Double(currentTokens) / Double(currentCount)
        let historicalAverage = Double(historyTokens) / Double(historyCount)
        guard currentAverage > 0, historicalAverage > 0 else { return nil }

        // Daily token buckets are a coarse bootstrap; percentage-based windows replace them.
        let relativePace = min(max(historicalAverage / currentAverage, 0.25), 4)
        return windowRate * relativePace
    }
}
