//
//  CodexClientError.swift
//  CodexLimits
//
//  Created by Erfan on 27/7/26.
//

import Foundation

enum CodexClientError: LocalizedError {
    case cliNotFound
    case invalidResponse
    case mainLimitMissing
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "Codex CLI was not found. Install it with Homebrew, sign in, and try again."
        case .invalidResponse:
            "Codex returned data this app could not read. Update Codex CLI and try again."
        case .mainLimitMissing:
            "Codex did not return a usable limit. Make sure Codex CLI is signed in."
        case .timedOut:
            "Codex took too long to respond. Try refreshing again."
        }
    }
}
