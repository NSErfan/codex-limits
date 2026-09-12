import Foundation

struct UsageSample: Codable, Equatable, Hashable, Sendable {
    let observedAt: Date
    let remainingPercent: Double
    let resetsAt: Date
    let durationMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case observedAt
        case date
        case remainingPercent
        case resetsAt
        case durationMinutes
    }

    init(observedAt: Date, remainingPercent: Double, resetsAt: Date, durationMinutes: Int? = nil) {
        self.observedAt = observedAt
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
        self.durationMinutes = durationMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        observedAt = try container.decodeIfPresent(Date.self, forKey: .observedAt)
            ?? container.decode(Date.self, forKey: .date)
        remainingPercent = try container.decode(Double.self, forKey: .remainingPercent)
        resetsAt = try container.decode(Date.self, forKey: .resetsAt)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(observedAt, forKey: .observedAt)
        try container.encode(remainingPercent, forKey: .remainingPercent)
        try container.encode(resetsAt, forKey: .resetsAt)
        try container.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
    }
}
