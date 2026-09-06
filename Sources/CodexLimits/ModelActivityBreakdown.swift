import Foundation

struct ModelActivityBreakdown {
    struct Slice: Identifiable, Equatable {
        let name: String
        let tokens: Int64
        var id: String { name }
    }

    let models: [Slice]
    private let contributions: [ModelActivityTimeline.Contribution]

    init(contributions: [ModelActivityTimeline.Contribution]) {
        self.contributions = contributions
        models = Self.slices(contributions, key: { $0.group.model })
    }

    func efforts(for model: String) -> [Slice] {
        Self.slices(contributions.filter { $0.group.model == model }, key: { $0.group.effort })
    }

    static func slice(at angle: Double?, in slices: [Slice]) -> String? {
        guard let angle, angle.isFinite, angle >= 0 else { return nil }
        var end: Double = 0
        for slice in slices {
            end += Double(slice.tokens)
            if angle < end { return slice.name }
        }
        return nil
    }

    private static func slices(_ contributions: [ModelActivityTimeline.Contribution],
                               key: (ModelActivityTimeline.Contribution) -> String) -> [Slice] {
        var totals: [String: Int64] = [:]
        for contribution in contributions {
            totals[key(contribution), default: 0] += contribution.tokens
        }
        return totals.filter { $0.value > 0 }.map { Slice(name: $0.key, tokens: $0.value) }.sorted {
            $0.tokens == $1.tokens ? $0.name < $1.name : $0.tokens > $1.tokens
        }
    }
}
