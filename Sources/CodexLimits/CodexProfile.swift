//
//  CodexProfile.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import Foundation

enum CodexProfile: Sendable {
    case primary
    case secondary

    static let secondaryUnsetEnvironmentKeys = [
        "CODEX_API_KEY", "OPENAI_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_ACCESS_TOKEN",
        "OPENAI_FEDERATION_RULE_ID", "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_IDENTITY_TOKEN_SOURCE",
        "OPENAI_WORKLOAD_IDENTITY_CONTEXT", "OPENAI_SPIFFE_AUDIENCE", "OPENAI_SPIFFE_ID",
        "OPENAI_SERVICE_ACCOUNT_ID", "CODEX_SQLITE_HOME"
    ]

    static var secondaryHome: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("com.github.nserfan.CodexLimits", isDirectory: true)
            .appendingPathComponent("CodexSecondaryProfile", isDirectory: true)
    }

    func home(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        switch self {
        case .primary:
            environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
                ?? URL.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        case .secondary:
            Self.secondaryHome
        }
    }

    static func validateSecondaryHome(
        _ home: URL = secondaryHome,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let primary = Self.primary.home(environment: environment)
        guard primary.resolvingSymlinksInPath().standardizedFileURL.path
            != home.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw CodexClientError.profileAlreadyInUse
        }
    }

    static func prepareSecondaryHome(
        _ home: URL = secondaryHome,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        try validateSecondaryHome(home, environment: environment)
        do {
            try FileManager.default.createDirectory(
                at: home, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw CodexClientError.profileUnavailable
        }
    }

    static func secondaryEnvironment(home: URL, base: [String: String]) -> [String: String] {
        var environment = base
        for key in secondaryUnsetEnvironmentKeys { environment.removeValue(forKey: key) }
        environment["CODEX_HOME"] = home.path
        return environment
    }
}
