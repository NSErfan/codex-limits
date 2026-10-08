import Foundation

enum CopilotClientError: UsageFetchError, Equatable, Sendable {
    case cliNotFound
    case credentialsMissing
    case unauthorized
    case forbidden
    case copilotUnavailable
    case rateLimited
    case httpStatus(Int)
    case requestFailed
    case invalidResponse
    case allowanceNotMetered
    case resetDateMissing
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "Couldn’t find the GitHub CLI (gh). Install it, sign in with gh auth login, then refresh."
        case .credentialsMissing:
            "The GitHub CLI isn’t signed in. Sign in with gh auth login, then refresh."
        case .unauthorized:
            "GitHub rejected the GitHub CLI’s saved login. Sign in again with gh auth login, then refresh."
        case .forbidden:
            "GitHub didn’t allow access to Copilot usage. Check that the GitHub CLI is signed in to an account with Copilot."
        case .copilotUnavailable:
            "GitHub didn’t find Copilot for the signed-in account. Sign the GitHub CLI in to an account with Copilot, then refresh."
        case .rateLimited:
            "GitHub is limiting requests. Refresh again in a few minutes."
        case let .httpStatus(status):
            "GitHub couldn’t load Copilot usage (HTTP \(status)). Try refreshing later."
        case .requestFailed:
            "Couldn’t reach GitHub through the GitHub CLI. Check your connection, then refresh."
        case .invalidResponse:
            "Couldn’t read GitHub’s Copilot usage response. Try refreshing or check for an app update."
        case .allowanceNotMetered:
            "GitHub doesn’t report a limited Copilot allowance for this account, so there’s no balance to track."
        case .resetDateMissing:
            "GitHub didn’t report when the Copilot allowance resets. Try refreshing later."
        case .timedOut:
            "The GitHub CLI didn’t respond in time. Refresh to try again."
        }
    }

    var shouldRetryAutomatically: Bool {
        switch self {
        case .requestFailed, .timedOut, .invalidResponse:
            true
        case let .httpStatus(status):
            status >= 500
        default:
            false
        }
    }

    var requiresLogin: Bool {
        switch self {
        case .cliNotFound, .credentialsMissing, .unauthorized:
            true
        default:
            false
        }
    }
}
