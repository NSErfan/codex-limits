import XCTest
@testable import CodexLimits

final class ClaudeCredentialsTests: XCTestCase {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let valid = Data(#"{"claudeAiOauth":{"accessToken":"fixture-token","refreshToken":"unused-secret","expiresAt":1800003600000,"scopes":["user:profile","user:inference"]}}"#.utf8)

    func testDecodesMillisecondsExpirationAndAccessTokenOnly() throws {
        let credentials = try ClaudeCredentials.decode(Self.valid, now: Self.now)
        XCTAssertEqual(credentials.accessToken, "fixture-token")
        XCTAssertEqual(credentials.expiresAt, Self.now.addingTimeInterval(3_600))
    }

    func testExpiredCredentialsRequireOfficialCLIRenewal() {
        XCTAssertThrowsError(try ClaudeCredentials.decode(Self.valid, now: Self.now.addingTimeInterval(3_600))) {
            XCTAssertEqual($0 as? ClaudeClientError, .credentialsExpired)
        }
    }

    func testMissingExpirationCanBeValidatedByTheServer() throws {
        let credentials = try ClaudeCredentials.decode(Data(#"{"claudeAiOauth":{"accessToken":"fixture"}}"#.utf8), now: Self.now)
        XCTAssertNil(credentials.expiresAt)
    }

    func testInvalidCredentialShapesAndHeaderInjectionAreRejected() {
        for payload in ["{}", "invalid", #"{"mcpOAuth":{}}"#, #"{"claudeAiOauth":{"accessToken":"  "}}"#, #"{"claudeAiOauth":{"accessToken":"token\r\nInjected: value"}}"#] {
            XCTAssertThrowsError(try ClaudeCredentials.decode(Data(payload.utf8), now: Self.now)) {
                XCTAssertEqual($0 as? ClaudeClientError, .credentialsInvalid)
            }
        }
    }

    func testInferenceOnlyTokenCannotReadAccountUsage() {
        let payload = Data(#"{"claudeAiOauth":{"accessToken":"fixture","scopes":["user:inference"]}}"#.utf8)
        XCTAssertThrowsError(try ClaudeCredentials.decode(payload, now: Self.now)) {
            XCTAssertEqual($0 as? ClaudeClientError, .missingProfileScope)
        }
    }

    func testPrefersKeychainWithoutReadingFallbackFile() throws {
        let credentials = try ClaudeCredentialReader.read(
            allowPrompt: false,
            now: Self.now,
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
            readKeychain: { service, allowPrompt in
                XCTAssertEqual(service, "Claude Code-credentials")
                XCTAssertFalse(allowPrompt)
                return Self.valid
            },
            readFile: { _ in
                XCTFail("A valid Keychain login should take precedence")
                return Data()
            }
        )
        XCTAssertEqual(credentials.accessToken, "fixture-token")
    }

    func testUsesCredentialFileWhenKeychainItemIsAbsent() throws {
        let credentials = try ClaudeCredentialReader.read(
            allowPrompt: false,
            now: Self.now,
            environment: [:],
            homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
            readKeychain: { _, _ in nil },
            readFile: { url in
                XCTAssertEqual(url.path, "/Users/fixture/.claude/.credentials.json")
                return Self.valid
            }
        )
        XCTAssertEqual(credentials.accessToken, "fixture-token")
    }

    func testMissingBothSourcesReportsLoginRequired() {
        XCTAssertThrowsError(try ClaudeCredentialReader.read(
            allowPrompt: false,
            readKeychain: { _, _ in nil },
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )) {
            XCTAssertEqual($0 as? ClaudeClientError, .credentialsMissing)
        }
    }

    func testExpiredKeychainLoginDoesNotFallBackToAnotherAccountsFile() {
        XCTAssertThrowsError(try ClaudeCredentialReader.read(
            allowPrompt: false,
            now: Self.now.addingTimeInterval(3_600),
            readKeychain: { _, _ in Self.valid },
            readFile: { _ in
                XCTFail("The existing Keychain account must remain authoritative")
                return Data(#"{"claudeAiOauth":{"accessToken":"other-account"}}"#.utf8)
            }
        )) {
            XCTAssertEqual($0 as? ClaudeClientError, .credentialsExpired)
        }
    }

    func testDeniedKeychainPreservesAccessRecoveryInsteadOfLogin() {
        XCTAssertThrowsError(try ClaudeCredentialReader.read(
            allowPrompt: false,
            readKeychain: { _, _ in throw ClaudeClientError.keychainAccessDenied },
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )) {
            let error = $0 as? ClaudeClientError
            XCTAssertEqual(error, .keychainAccessDenied)
            XCTAssertEqual(error?.requiresLogin, false)
            XCTAssertEqual(error?.shouldRetryAutomatically, false)
        }
    }

    func testExplicitRefreshCanPermitKeychainPrompt() throws {
        _ = try ClaudeCredentialReader.read(
            allowPrompt: true,
            now: Self.now,
            readKeychain: { _, allowPrompt in
                XCTAssertTrue(allowPrompt)
                return Self.valid
            },
            readFile: { _ in throw CocoaError(.fileReadNoSuchFile) }
        )
    }

    func testCustomProfilesNeverReadDefaultProfileCredentials() throws {
        let credentials = try ClaudeCredentialReader.read(
            allowPrompt: false,
            now: Self.now,
            environment: ["CLAUDE_CONFIG_DIR": "/profiles/work"],
            readKeychain: { service, _ in
                XCTAssertEqual(service, "Claude Code-credentials-2ea9e238")
                return nil
            },
            readFile: { url in
                XCTAssertEqual(url.path, "/profiles/work/.credentials.json")
                return Self.valid
            }
        )
        XCTAssertEqual(credentials.accessToken, "fixture-token")
    }

    func testEmptySecureStorageOverrideSelectsDefaultProfile() {
        let location = ClaudeCredentialReader.location(
            environment: ["CLAUDE_CONFIG_DIR": "/profiles/work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": ""],
            homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(location.service, "Claude Code-credentials")
        XCTAssertEqual(location.file.path, "/Users/fixture/.claude/.credentials.json")
    }

    func testRelativeConfigDirectoryRemainsLiteral() {
        let location = ClaudeCredentialReader.location(
            environment: ["CLAUDE_CONFIG_DIR": "~/profile"],
            homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
            workingDirectory: URL(fileURLWithPath: "/tmp")
        )
        XCTAssertEqual(location.file.path, "/tmp/~/profile/.credentials.json")
    }
}
