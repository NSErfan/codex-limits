import Foundation

enum ClaudeAccountReader {
    struct Account: Equatable, Sendable {
        let accountID: String
        let email: String
    }

    static func read(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:),
        readFile: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) -> Account? {
        let configured = environment["CLAUDE_CONFIG_DIR"]?.precomposedStringWithCanonicalMapping ?? ""
        let directory: URL
        if configured.isEmpty {
            directory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
        } else {
            directory = configured.hasPrefix("/")
                ? URL(fileURLWithPath: configured, isDirectory: true)
                : workingDirectory.appendingPathComponent(configured, isDirectory: true)
        }
        let credentialsDirectory = ClaudeProfile.location(
            environment: environment,
            homeDirectory: homeDirectory,
            workingDirectory: workingDirectory
        ).directory
        // Separate secure-storage roots do not establish which account owns this profile's metadata.
        guard directory.standardizedFileURL.resolvingSymlinksInPath()
            == credentialsDirectory.standardizedFileURL.resolvingSymlinksInPath() else { return nil }

        let legacyFile = directory.appendingPathComponent(".config.json")
        let accountFile = fileExists(legacyFile.path)
            ? legacyFile
            : (configured.isEmpty ? homeDirectory : directory).appendingPathComponent(".claude.json")
        guard let data = try? readFile(accountFile),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let account = payload.oauthAccount,
              let accountID = normalized(account.accountUuid),
              let email = normalized(account.emailAddress) else { return nil }
        return Account(accountID: accountID, email: email)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
        return trimmed
    }

    private struct Payload: Decodable {
        let oauthAccount: OAuthAccount?
    }

    private struct OAuthAccount: Decodable {
        let accountUuid: String?
        let emailAddress: String?
    }
}
