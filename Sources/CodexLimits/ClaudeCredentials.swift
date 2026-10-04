import Foundation

struct ClaudeCredentials: Sendable {
    let accessToken: String
    let expiresAt: Date?

    static func decode(_ data: Data, now: Date) throws -> ClaudeCredentials {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              let oauth = payload.claudeAiOauth,
              let rawToken = oauth.accessToken else {
            throw ClaudeClientError.credentialsInvalid
        }
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty,
              !token.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            throw ClaudeClientError.credentialsInvalid
        }
        if let scopes = oauth.scopes, !scopes.contains("user:profile") {
            throw ClaudeClientError.missingProfileScope
        }
        let expiration = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1_000) }
        if let expiration, expiration <= now {
            // The CLI owns refresh-token rotation. Re-read its credentials on the next fetch.
            throw ClaudeClientError.credentialsExpired
        }
        return ClaudeCredentials(accessToken: token, expiresAt: expiration)
    }

    private struct Payload: Decodable {
        let claudeAiOauth: OAuth?
    }

    private struct OAuth: Decodable {
        let accessToken: String?
        let expiresAt: Double?
        let scopes: [String]?
    }
}
