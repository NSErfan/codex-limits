import Foundation

enum ClaudeClientError: UsageFetchError, Equatable, Sendable {
    case credentialsMissing
    case cliNotFound
    case cliUpdateRequired
    case commandFailed
    case usageUnavailable
    case unauthorized
    case forbidden
    case rateLimited(retryAfter: Date?)
    case serverError(Int)
    case invalidResponse
    case mainLimitMissing
    case networkUnavailable
    case timedOut

    var errorDescription: String? {
        switch self {
        case .credentialsMissing:
            "Claude Code isn’t signed in. Sign in with your Claude subscription, then refresh."
        case .cliNotFound:
            "Couldn’t launch Claude Code. Install or update the Claude Code CLI, then refresh."
        case .cliUpdateRequired:
            "Claude Code didn’t provide structured subscription usage. Update Claude Code and check /usage in Terminal, then refresh."
        case .commandFailed:
            "Claude Code couldn’t run its usage command. Update Claude Code and try /usage in Terminal, then refresh."
        case .usageUnavailable:
            "Claude Code couldn’t retrieve subscription usage. Check your login and connection with /usage in Claude Code, then refresh."
        case .unauthorized:
            "Claude rejected the saved login. Open Claude Code or sign in again, then refresh."
        case .forbidden:
            "Claude didn’t allow access to subscription usage. Check that Claude Code is signed in with a supported Claude subscription."
        case .rateLimited:
            "Claude is limiting usage checks. Usage checks will resume after the cooldown."
        case let .serverError(status):
            "Claude couldn’t load usage (HTTP \(status)). Try refreshing later."
        case .invalidResponse:
            "Couldn’t read Claude’s usage response. Try refreshing or check for an app update."
        case .mainLimitMissing:
            "Claude didn’t return a usage window with a reset time. Refresh after using Claude Code."
        case .networkUnavailable:
            "Couldn’t connect to Claude. Check your internet connection, then refresh."
        case .timedOut:
            "Claude didn’t respond in time. Refresh to try again."
        }
    }

    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    var shouldRetryAutomatically: Bool {
        switch self {
        case .networkUnavailable, .timedOut, .invalidResponse, .usageUnavailable:
            true
        case let .serverError(status):
            status >= 500
        default:
            false
        }
    }

    var requiresLogin: Bool {
        switch self {
        case .credentialsMissing, .unauthorized:
            true
        default:
            false
        }
    }
}
