enum UsagePeriod: String, CaseIterable, Codable, Identifiable, Sendable {
    case fiveHour
    case weekly
    case monthly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        }
    }

    /// Nominal length, which also names the period's history folder. Calendar
    /// months vary, so classify windows with `includes(durationMinutes:)`.
    var durationMinutes: Int {
        switch self {
        case .fiveHour: 300
        case .weekly: 10_080
        case .monthly: 43_200
        }
    }

    func includes(durationMinutes minutes: Int?) -> Bool {
        guard let minutes else { return false }
        switch self {
        case .fiveHour, .weekly: return minutes == durationMinutes
        case .monthly: return (28 * 1_440 ... 31 * 1_440).contains(minutes)
        }
    }
}
