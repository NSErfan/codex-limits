enum UsagePeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    case fiveHour
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        }
    }

    var durationMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .weekly: 10_080
        }
    }
}
