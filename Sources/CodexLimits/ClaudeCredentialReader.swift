import CryptoKit
import Foundation
import LocalAuthentication
import Security

enum ClaudeCredentialReader {
    private static let keychainLock = NSLock()

    static func read(
        allowPrompt: Bool,
        now: Date = Date(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        readKeychain: (String, Bool) throws -> Data? = readKeychain,
        readFile: (URL) throws -> Data = { try Data(contentsOf: $0) }
    ) throws -> ClaudeCredentials {
        let location = location(
            environment: environment,
            homeDirectory: homeDirectory,
            workingDirectory: workingDirectory
        )
        var keychainError: Error?
        var keychainData: Data?
        do {
            keychainData = try readKeychain(location.service, allowPrompt)
        } catch {
            keychainError = error
        }
        if let keychainData {
            // An existing Keychain login is authoritative; an old fallback file may belong to another account.
            return try ClaudeCredentials.decode(keychainData, now: now)
        }

        do {
            let data = try readFile(location.file)
            return try ClaudeCredentials.decode(data, now: now)
        } catch let error as ClaudeClientError {
            throw error
        } catch {
            if let keychainError { throw keychainError }
            if (error as NSError).domain == NSCocoaErrorDomain,
               (error as NSError).code == NSFileReadNoSuchFileError {
                throw ClaudeClientError.credentialsMissing
            }
            throw ClaudeClientError.credentialsInvalid
        }
    }

    static func location(
        environment: [String: String],
        homeDirectory: URL,
        workingDirectory: URL
    ) -> (service: String, file: URL) {
        let configured = environment["CLAUDE_SECURESTORAGE_CONFIG_DIR"]
            ?? environment["CLAUDE_CONFIG_DIR"]
        let path = configured?.precomposedStringWithCanonicalMapping ?? ""
        let directory: URL
        let service: String
        if path.isEmpty {
            directory = homeDirectory.appendingPathComponent(".claude", isDirectory: true)
            service = "Claude Code-credentials"
        } else {
            directory = path.hasPrefix("/")
                ? URL(fileURLWithPath: path, isDirectory: true)
                : workingDirectory.appendingPathComponent(path, isDirectory: true)
            // Claude Code namespaces custom profile Keychain items with the first eight SHA-256 digits.
            let suffix = SHA256.hash(data: Data(path.utf8))
                .prefix(4).map { String(format: "%02x", $0) }.joined()
            service = "Claude Code-credentials-\(suffix)"
        }
        return (service, directory.appendingPathComponent(".credentials.json"))
    }

    private static func readKeychain(service: String, allowPrompt: Bool) throws -> Data? {
        keychainLock.lock()
        defer { keychainLock.unlock() }
        // LAContext alone does not suppress legacy login-Keychain ACL dialogs. Serialize the
        // process-wide interaction policy and restore it so background reads cannot open one.
        var interactionWasAllowed = DarwinBoolean(false)
        guard SecKeychainGetUserInteractionAllowed(&interactionWasAllowed) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(allowPrompt) == errSecSuccess else {
            throw ClaudeClientError.keychainAccessDenied
        }
        defer { SecKeychainSetUserInteractionAllowed(interactionWasAllowed.boolValue) }
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]
        var result: CFTypeRef?
        switch SecItemCopyMatching(query as CFDictionary, &result) {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw ClaudeClientError.credentialsInvalid
            }
            return data
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed, errSecAuthFailed, errSecUserCanceled:
            throw ClaudeClientError.keychainAccessDenied
        default:
            throw ClaudeClientError.credentialsInvalid
        }
    }
}
