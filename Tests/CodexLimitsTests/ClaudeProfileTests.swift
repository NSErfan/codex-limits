import XCTest
@testable import CodexLimits

final class ClaudeProfileTests: XCTestCase {
    func testDefaultProfilePreservesExistingRefreshNamespace() {
        let location = profile([:])
        XCTAssertEqual(location.identifier, "Claude Code-credentials")
        XCTAssertEqual(location.directory.path, "/Users/fixture/.claude")
    }

    func testCustomProfilePreservesExistingRefreshNamespace() {
        let location = profile(["CLAUDE_CONFIG_DIR": "/profiles/work"])
        XCTAssertEqual(location.identifier, "Claude Code-credentials-2ea9e238")
        XCTAssertEqual(location.directory.path, "/profiles/work")
    }

    func testEmptySecureStorageOverrideSelectsDefaultProfile() {
        let location = profile(["CLAUDE_CONFIG_DIR": "/profiles/work", "CLAUDE_SECURESTORAGE_CONFIG_DIR": ""])
        XCTAssertEqual(location.identifier, "Claude Code-credentials")
        XCTAssertEqual(location.directory.path, "/Users/fixture/.claude")
    }

    func testRelativeConfigDirectoryRemainsLiteral() {
        let location = profile(["CLAUDE_CONFIG_DIR": "~/profile"])
        XCTAssertEqual(location.directory.path, "/tmp/~/profile")
    }

    private func profile(_ environment: [String: String]) -> (identifier: String, directory: URL) {
        ClaudeProfile.location(environment: environment,
                               homeDirectory: URL(fileURLWithPath: "/Users/fixture"),
                               workingDirectory: URL(fileURLWithPath: "/tmp"))
    }
}
