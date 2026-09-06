import Foundation

struct ModelActivityTimeline {
    enum Metric: String, CaseIterable, Identifiable {
        case total = "Total tokens", output = "Output tokens"
        var id: Self { self }
        func value(_ tokens: ModelActivityEvent.Tokens) -> Int64 {
            self == .total ? tokens.total : tokens.output
        }
    }

    struct Contribution: Identifiable {
        let group: ModelActivityEvent.Group
        var tokens: Int64
        var events: Int
        var id: ModelActivityEvent.Group { group }
    }

    struct Interval: Identifiable {
        let start: Date
        let end: Date
        var contributions: [Contribution]
        var total: Int64
        var matched: Int64
        let hasMatches: Bool
        var id: Date { start }
    }

    struct Highlight: Identifiable {
        let start: Date
        var end: Date
        var id: Date { start }
    }

    struct ModelSegment: Identifiable {
        let model: String
        let start: Date
        let end: Date
        let lower: Int64
        let upper: Int64
        let lane: Int
        var id: String { "\(start.timeIntervalSince1970)|\(model)" }
    }

    let modelSegments: [ModelSegment]
    let matchedModels: [String]
    let summary: Interval
    let highlights: [Highlight]
    let range: ClosedRange<Date>
    let intervals: [Interval]
    let total: Int64
    let matched: Int64
    let activeIntervals: Int
    let matchingIntervals: Int

    init(events: [ModelActivityEvent], range: ClosedRange<Date>, intervalDuration: TimeInterval,
         metric: Metric, models: Set<String>?, efforts: Set<String>?) {
        self.range = range
        let duration = max(intervalDuration, 60)
        let first = floor(range.lowerBound.timeIntervalSince1970 / duration) * duration
        let count = max(1, Int(ceil((range.upperBound.timeIntervalSince1970 - first) / duration)))
        var grouped = Array(repeating: [ModelActivityEvent.Group: Contribution](), count: count)
        for event in events where event.date >= range.lowerBound && event.date < range.upperBound {
            let index = Int(floor((event.date.timeIntervalSince1970 - first) / duration))
            guard grouped.indices.contains(index) else { continue }
            let value = metric.value(event.tokens)
            var contribution = grouped[index][event.group] ?? .init(group: event.group, tokens: 0, events: 0)
            contribution.tokens += value
            contribution.events += 1
            grouped[index][event.group] = contribution
        }
        intervals = grouped.enumerated().map { index, groups in
            let start = Date(timeIntervalSince1970: first + Double(index) * duration)
            let contributions = groups.values.sorted {
                $0.tokens == $1.tokens ? $0.group.label < $1.group.label : $0.tokens > $1.tokens
            }
            let total = contributions.reduce(Int64(0)) { $0 + $1.tokens }
            let matching = contributions.filter {
                (models?.contains($0.group.model) ?? true) && (efforts?.contains($0.group.effort) ?? true)
            }
            let matched = matching.reduce(Int64(0)) { $0 + $1.tokens }
            return Interval(start: max(start, range.lowerBound), end: min(start.addingTimeInterval(duration), range.upperBound),
                            contributions: contributions, total: total, matched: matched, hasMatches: !matching.isEmpty)
        }
        matchedModels = Set(intervals.flatMap(\.contributions).filter {
            (models?.contains($0.group.model) ?? true) && (efforts?.contains($0.group.effort) ?? true)
        }.map(\.group.model)).sorted()
        let lanes = Dictionary(uniqueKeysWithValues: matchedModels.enumerated().map { ($0.element, $0.offset) })
        modelSegments = intervals.flatMap { interval in
            let selected = interval.contributions.filter {
                (models?.contains($0.group.model) ?? true) && (efforts?.contains($0.group.effort) ?? true)
            }
            let byModel = Dictionary(grouping: selected, by: \.group.model)
            var lower: Int64 = 0
            return byModel.keys.sorted().map { model in
                let tokens = byModel[model, default: []].reduce(Int64(0)) { $0 + $1.tokens }
                defer { lower += tokens }
                return ModelSegment(model: model, start: interval.start, end: interval.end,
                                    lower: lower, upper: lower + tokens, lane: lanes[model] ?? 0)
            }
        }
        total = intervals.reduce(0) { $0 + $1.total }
        matched = intervals.reduce(0) { $0 + $1.matched }
        activeIntervals = intervals.filter { !$0.contributions.isEmpty }.count
        matchingIntervals = intervals.filter(\.hasMatches).count
        var regions: [Highlight] = []
        for interval in intervals where interval.hasMatches {
            if regions.last?.end == interval.start {
                regions[regions.count - 1].end = interval.end
            } else {
                regions.append(.init(start: interval.start, end: interval.end))
            }
        }
        highlights = regions
        var contributions: [ModelActivityEvent.Group: Contribution] = [:]
        for interval in intervals {
            for item in interval.contributions {
                var combined = contributions[item.group] ?? .init(group: item.group, tokens: 0, events: 0)
                combined.tokens += item.tokens
                combined.events += item.events
                contributions[item.group] = combined
            }
        }
        summary = Interval(start: range.lowerBound, end: range.upperBound,
                           contributions: contributions.values.sorted {
                               $0.tokens == $1.tokens ? $0.group.label < $1.group.label : $0.tokens > $1.tokens
                           }, total: total, matched: matched, hasMatches: matchingIntervals > 0)

    }

    func interval(at date: Date?) -> Interval? {
        guard let date else { return intervals.last(where: { !$0.contributions.isEmpty }) }
        return intervals.first { $0.start <= date && date < $0.end }
            ?? (date == range.upperBound ? intervals.last : nil)
    }
}
