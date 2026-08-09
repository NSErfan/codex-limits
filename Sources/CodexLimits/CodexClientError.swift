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
            "Codex CLI was not found. Install it with Homebrew, sign in, and try again."
        case .invalidResponse:
            "Codex returned data this app could not read. Update Codex CLI and try again."
        case let .appServerError(message):
            Self.appServerMessage(message)
        case .mainLimitMissing:
            "Codex did not return a usable limit. Make sure Codex CLI is signed in."
        case .timedOut:
            "Codex took too long to respond. Try refreshing again."
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
            return "Codex couldn’t load usage. Refresh to try again."
        }
        let hasTerminalPunctuation = detail.last.map { ".!?".contains($0) } ?? false
        let punctuation = hasTerminalPunctuation ? "" : "."
        return "Codex couldn’t load usage: \(detail)\(punctuation) Refresh to try again."
    }
}
