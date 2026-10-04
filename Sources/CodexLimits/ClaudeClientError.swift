import Foundation

enum ClaudeClientError: UsageFetchError, Equatable, Sendable {
    case credentialsMissing
    case credentialsInvalid
    case credentialsExpired
    case keychainAccessDenied
    case missingProfileScope
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
        case .credentialsInvalid:
            "Couldn’t read Claude Code’s login. Sign in again with your Claude subscription, then refresh."
        case .credentialsExpired:
            "Claude Code’s login has expired. Open Claude Code to renew it, or sign in again, then refresh."
        case .keychainAccessDenied:
            "Claude Code’s login is in your Keychain. Click Refresh and allow access when macOS asks."
        case .missingProfileScope:
            "This Claude token can’t read account usage. Sign in with your Claude subscription using Claude Code, then refresh."
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

    var shouldRetryAutomatically: Bool {
        switch self {
        case .networkUnavailable, .timedOut, .invalidResponse:
            true
        case let .serverError(status):
            status >= 500
        default:
            false
        }
    }

    var requiresLogin: Bool {
        switch self {
        case .credentialsMissing, .credentialsInvalid, .credentialsExpired,
             .missingProfileScope, .unauthorized:
            true
        default:
            false
        }
    }
}
