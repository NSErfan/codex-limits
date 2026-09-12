import Foundation

struct HistoricalForecast {
    let date: Date
    let lastReading: UsageSample
    let window: UsageWindow
    let samples: [UsageSample]
    let forecast: Forecast
    let assumedDuration: Bool

    enum Unavailable: LocalizedError, Equatable {
        case futureDate
        case noReading
        case resetPassed
        case invalidWindow
        case invalidLegacyWindow

        var errorDescription: String? {
            switch self {
            case .futureDate: "Choose a date and time in the past."
            case .noReading: "No recorded reading exists at or before this time. Choose a later time."
            case .resetPassed: "The last recorded limit had already reset, and no reading of the next window was available yet. Choose a time with a recorded balance."
            case .invalidWindow: "The recorded window is invalid for this reading. Choose a different time."
            case .invalidLegacyWindow: "The chosen window length does not contain the last reading. Try a different window length or date."
            }
        }
    }

    static func reconstruct(
        at date: Date,
        samples: [UsageSample],
        legacyDurationMinutes: Int,
        safetyBuffer: Double,
        now: Date
    ) -> Result<Self, Unavailable> {
        guard date <= now else { return .failure(.futureDate) }
        // Every forecast input is cut off here, including other reset windows.
        // Later percentage readings must not influence a reconstruction.
        let recorded = samples.filter {
            $0.observedAt <= date && $0.remainingPercent.isFinite
                && (0 ... 100).contains($0.remainingPercent)
        }.sorted {
            if $0.observedAt != $1.observedAt { return $0.observedAt < $1.observedAt }
            if ($0.durationMinutes != nil) != ($1.durationMinutes != nil) { return $0.durationMinutes == nil }
            if $0.resetsAt != $1.resetsAt { return $0.resetsAt < $1.resetsAt }
            return $0.remainingPercent > $1.remainingPercent
        }
        guard let reading = recorded.last else { return .failure(.noReading) }
        guard date < reading.resetsAt else { return .failure(.resetPassed) }
        let recordedDuration = reading.durationMinutes ?? recorded.last(where: {
            UsageWindow.hasSameReset($0.resetsAt, reading.resetsAt) && $0.durationMinutes != nil
        })?.durationMinutes
        let duration = recordedDuration ?? legacyDurationMinutes
        guard duration > 0 else { return .failure(.invalidWindow) }
        let window = UsageWindow(remainingPercent: reading.remainingPercent, resetsAt: reading.resetsAt,
                                 durationMinutes: duration)
        guard reading.observedAt >= window.startsAt, date >= window.startsAt else {
            return .failure(recordedDuration == nil ? .invalidLegacyWindow : .invalidWindow)
        }
        let compatible = recorded.filter {
            ($0.durationMinutes == duration || ($0.durationMinutes == nil && UsageWindow.hasSameReset($0.resetsAt, window.resetsAt)))
                && $0.observedAt < $0.resetsAt
                && $0.observedAt >= $0.resetsAt.addingTimeInterval(-Double(duration) * 60)
        }
        let forecast = ForecastEngine.evaluate(
            window: window, samples: compatible, tokenHistory: [], safetyBuffer: safetyBuffer,
            now: date, previousStatus: nil
        )
        return .success(Self(date: date, lastReading: reading, window: window,
                             samples: compatible.filter { UsageWindow.hasSameReset($0.resetsAt, window.resetsAt) },
                             forecast: forecast, assumedDuration: recordedDuration == nil))
    }
}
