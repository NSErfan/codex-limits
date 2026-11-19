//
//  CodexProfile.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import Foundation

enum CodexProfile {
    static let credentialEnvironmentKeys = [
        "CODEX_API_KEY", "OPENAI_API_KEY", "CODEX_ACCESS_TOKEN", "OPENAI_ACCESS_TOKEN",
        "OPENAI_IDENTITY_TOKEN_FILE", "OPENAI_SERVICE_ACCOUNT_ID"
    ]

    static var secondaryHome: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("com.github.nserfan.CodexLimits", isDirectory: true)
            .appendingPathComponent("CodexSecondaryProfile", isDirectory: true)
    }

    static func prepareSecondaryHome(
        _ home: URL = secondaryHome,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        let primary = environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
            ?? URL.homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        let resolvedPrimary = primary.resolvingSymlinksInPath().standardizedFileURL.path
        guard resolvedPrimary != home.resolvingSymlinksInPath().standardizedFileURL.path else {
            throw CodexClientError.profileAlreadyInUse
        }
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
        for key in credentialEnvironmentKeys { environment.removeValue(forKey: key) }
        environment["CODEX_HOME"] = home.path
        return environment
    }
}
