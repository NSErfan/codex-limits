import CodexWidgetKit

enum MenuBarUsageWindow: String, CaseIterable, Identifiable {
    case automatic
    case fiveHour
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .fiveHour: "5-hour"
        case .weekly: "Weekly"
        }
    }

    var shortTitle: String {
        switch self {
        case .automatic: "Automatic"
        case .fiveHour: "5h"
        case .weekly: "Week"
        }
    }

    static func options(for provider: UsageProvider) -> [Self] {
        allCases.filter { selection in
            selection.period.map { provider.periods.contains($0) } ?? true
        }
    }

    func limit(in snapshot: UsageSnapshot?, provider: UsageProvider) -> LimitReading? {
        guard let snapshot else { return nil }
        guard let period, provider.periods.contains(period) else { return snapshot.mainLimit }
        guard let limit = snapshot.limit(for: period, provider: provider),
              limit.window.remainingPercent.isFinite,
              (0 ... 100).contains(limit.window.remainingPercent),
              snapshot.fetchedAt <= limit.window.resetsAt else { return nil }
        return limit
    }

    private var period: UsagePeriod? {
        switch self {
        case .automatic: nil
        case .fiveHour: .fiveHour
        case .weekly: .weekly
        }
    }
}
