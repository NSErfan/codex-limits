import Foundation

enum UsageFetchResult: Sendable {
    case fetched(UsageSnapshot, nextRefreshAt: Date? = nil)
    case cached(UsageSnapshot, nextRefreshAt: Date)
    case deferred(any UsageFetchError, snapshot: UsageSnapshot?, nextRefreshAt: Date? = nil)

    var nextRefreshAt: Date? {
        switch self {
        case let .fetched(_, date), let .deferred(_, _, date): date
        case let .cached(_, date): date
        }
    }
}
