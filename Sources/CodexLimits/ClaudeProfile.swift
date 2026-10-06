import CryptoKit
import Foundation

enum ClaudeProfile {
    static func location(
        environment: [String: String],
        homeDirectory: URL,
        workingDirectory: URL
    ) -> (identifier: String, directory: URL) {
        let configured = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
            ?? environment["CLAUDE_CONFIG_DIR"]
        let path = configured?.precomposedStringWithCanonicalMapping ?? ""
        let directory: URL
        let identifier: String
        if path.isEmpty {
            directory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
            identifier = "Claude Code-credentials"
        } else {
            directory = path.hasPrefix("/")
                ? URL(fileURLWithPath: path, isDirectory: true)
                : workingDirectory.appendingPathComponent(path, isDirectory: true)
            // Preserve the CLI profile namespace so existing refresh reservations survive app upgrades.
            let suffix = SHA256.hash(data: Data(path.utf8))
                .prefix(4).map { String(format: "%02x", $0) }.joined()
            identifier = "Claude Code-credentials-\(suffix)"
        }
        return (identifier, directory)
    }
}
