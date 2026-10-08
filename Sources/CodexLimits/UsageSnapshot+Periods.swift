import CodexWidgetKit

extension UsageSnapshot {
    func limit(for period: UsagePeriod, provider: UsageProvider) -> LimitReading? {
        ([mainLimit] + otherLimits).first {
            $0.limitId == provider.rawValue && period.includes(durationMinutes: $0.window.durationMinutes)
        }
    }

    func sample(for period: UsagePeriod, provider: UsageProvider) -> UsageSample? {
        guard let window = limit(for: period, provider: provider)?.window,
              fetchedAt <= window.resetsAt,
              window.remainingPercent.isFinite,
              (0 ... 100).contains(window.remainingPercent) else { return nil }
        return UsageSample(
            observedAt: fetchedAt,
            remainingPercent: window.remainingPercent,
            resetsAt: window.resetsAt,
            durationMinutes: window.durationMinutes
        )
    }
}
