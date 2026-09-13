//
//  CodexClientError.swift
//  CodexLimits
//
//  Created by Erfan on 27/7/26.
//

import Foundation

enum CodexClientError: LocalizedError, Sendable {
    case cliNotFound
    case invalidResponse
    case appServerError(String)
    case mainLimitMissing
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "Codex CLI wasn’t found. Install it and sign in, then try again."
        case .invalidResponse:
            "Couldn’t read the response from Codex. Try refreshing. If this continues, check for updates to Codex CLI and Codex Limits."
        case let .appServerError(message):
            Self.appServerMessage(message)
        case .mainLimitMissing:
            "Codex didn’t return usage-limit information. Check that Codex CLI is signed in, then refresh."
        case .timedOut:
            "Codex didn’t respond in time. Refresh to try again."
        }
    }

    var shouldRetryAutomatically: Bool {
        switch self {
        case .invalidResponse, .appServerError, .timedOut:
            true
        case .cliNotFound, .mainLimitMissing:
            false
        }
    }

    private static func appServerMessage(_ message: String) -> String {
        let detail = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.isEmpty else {
            return "Couldn’t load Codex usage. Refresh to try again."
        }
        let hasTerminalPunctuation = detail.last.map { ".!?".contains($0) } ?? false
        let punctuation = hasTerminalPunctuation ? "" : "."
        return "Couldn’t load Codex usage. \(detail)\(punctuation) Refresh to try again."
    }
}
