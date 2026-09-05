import Foundation

/// The only data shared with the extension: percentages and dates, never CLI responses.
public struct WeeklyWidgetSnapshot: Codable, Equatable, Sendable {
    public struct Window: Codable, Equatable, Sendable {
        public let remainingPercent: Double
        public let startsAt: Date
        public let resetsAt: Date

        public init(remainingPercent: Double, startsAt: Date, resetsAt: Date) {
            self.remainingPercent = remainingPercent
            self.startsAt = startsAt
            self.resetsAt = resetsAt
        }
    }

    public struct Sample: Codable, Equatable, Hashable, Sendable {
        public let date: Date
        public let remainingPercent: Double

        public init(date: Date, remainingPercent: Double) {
            self.date = date
            self.remainingPercent = remainingPercent
        }
    }

    public enum Status: Sendable {
        case current, stale, expired, unavailable
    }

    public static let staleInterval: TimeInterval = 30 * 60
    public let version: Int
    public let fetchedAt: Date
    public let window: Window?
    public let samples: [Sample]

    public init(fetchedAt: Date, window: Window?, samples: [Sample] = []) {
        version = 1
        self.fetchedAt = fetchedAt
        self.window = window
        self.samples = samples
    }

    public func status(at date: Date) -> Status {
        guard version == 1, let window,
              window.remainingPercent.isFinite,
              (0 ... 100).contains(window.remainingPercent),
              window.startsAt <= fetchedAt, fetchedAt < window.resetsAt else {
            return .unavailable
        }
        if date >= window.resetsAt { return .expired }
        return date.timeIntervalSince(fetchedAt) >= Self.staleInterval ? .stale : .current
    }

    /// Merge only readings from the same weekly cycle. Keep the newest observation
    /// at the endpoint, and never draw a reset as if it were consumption.
    public func merging(_ previous: [WeeklyWidgetSnapshot]) -> WeeklyWidgetSnapshot {
        guard let window, status(at: fetchedAt) != .unavailable else { return self }
        let matching = previous.filter {
            guard $0.version == 1, let oldWindow = $0.window else { return false }
            return abs(oldWindow.resetsAt.timeIntervalSince(window.resetsAt)) <= 60
        }
        let candidates = matching.flatMap(\.samples) + samples
        var byDate: [Date: Double] = [:]
        for sample in candidates where sample.date >= window.startsAt
            && sample.date < fetchedAt
            && sample.remainingPercent.isFinite
            && (0 ... 100).contains(sample.remainingPercent) {
            byDate[sample.date] = min(byDate[sample.date] ?? 100, sample.remainingPercent)
        }
        byDate[fetchedAt] = window.remainingPercent
        let ordered = byDate.map { Sample(date: $0.key, remainingPercent: $0.value) }
            .sorted { $0.date < $1.date }
        // At ten-minute collection cadence a full week is 1,009 points. Bound
        // unusually frequent manual refreshes while retaining the whole curve.
        let bounded: [Sample]
        if ordered.count > 1_200 {
            bounded = (0 ..< 1_200).map { index in
                ordered[index * (ordered.count - 1) / 1_199]
            }
        } else {
            bounded = ordered
        }
        return Self(fetchedAt: fetchedAt, window: window, samples: bounded)
    }

    /// Synthetic readings, used only by WidgetKit's gallery and explicit previews.
    public static func preview(at date: Date = .now, remaining: Double = 68) -> Self {
        let start = date.addingTimeInterval(-3 * 86_400)
        let window = Window(
            remainingPercent: remaining,
            startsAt: start,
            resetsAt: start.addingTimeInterval(7 * 86_400)
        )
        let levels: [Double] = [100, 99, 97, 97, 91, 89, 89, 84, 83, 79, 76, 76, 72, 68]
        return Self(fetchedAt: date, window: window, samples: levels.enumerated().map {
            Sample(
                date: start.addingTimeInterval(Double($0.offset) / Double(levels.count - 1) * 3 * 86_400),
                remainingPercent: remaining + ($0.element - 68) / 32 * (100 - remaining)
            )
        })
    }
}
