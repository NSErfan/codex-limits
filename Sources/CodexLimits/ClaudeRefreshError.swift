import Foundation

enum ClaudeRefreshError: UsageFetchError {
    case rateLimited(until: Date)
    case tooSoon(until: Date)
    case inProgress
    case storageUnavailable
    case failed(ClaudeClientError, until: Date)

    var requiresLogin: Bool {
        if case let .failed(error, _) = self { return error.requiresLogin }
        return false
    }
    var shouldRetryAutomatically: Bool { false }

    var errorDescription: String? {
        switch self {
        case let .rateLimited(until):
            "Claude paused usage checks. Next check available \(until.formatted(date: .abbreviated, time: .shortened)). Refresh cannot bypass this cooldown."
        case let .tooSoon(until):
            "Claude usage checks are spaced 15 minutes apart. Next check available \(until.formatted(date: .abbreviated, time: .shortened))."
        case .inProgress:
            "Another Claude usage check is in progress. Showing the last reading; try again shortly."
        case .storageUnavailable:
            "Couldn’t read or save Claude’s refresh schedule. Usage checks are paused to avoid repeated requests."
        case let .failed(error, until):
            "\(error.localizedDescription) Next usage check available \(until.formatted(date: .abbreviated, time: .shortened))."
        }
    }
}
