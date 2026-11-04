import XCTest
@testable import CodexLimits

final class ClaudeAuthStatusTests: XCTestCase {
    func testSignedOutStatusIsRecognizedDespiteFailingExit() async throws {
        let fixture = try Fixture(script: #"""
        [ "$*" = "auth status --json" ] || exit 9
        printf '{"loggedIn":false,"authMethod":"none"}\n'
        exit 1
        """#)
        defer { fixture.cleanUp() }
        let signedOut = try await ClaudeAuthStatus.isSignedOut(executable: fixture.executable.path)
        XCTAssertTrue(signedOut)
    }

    func testSignedInOrUnreadableStatusIsNotTreatedAsSignedOut() async throws {
        for script in [
            #"printf '{"loggedIn":true,"authMethod":"claude.ai"}\n'"#,
            "echo 'Not logged in. Run claude auth login to authenticate.'\nexit 1",
            #"printf '{"authMethod":"none"}\n'; exit 1"#,
            "exit 1"
        ] {
            let fixture = try Fixture(script: script)
            defer { fixture.cleanUp() }
            let signedOut = try await ClaudeAuthStatus.isSignedOut(executable: fixture.executable.path)
            XCTAssertFalse(signedOut, script)
        }
        let missing = try await ClaudeAuthStatus.isSignedOut(executable: "/missing/claude")
        XCTAssertFalse(missing)
    }

    func testStalledStatusCheckIsNotTreatedAsSignedOut() async throws {
        let fixture = try Fixture(script: "while :; do :; done")
        defer { fixture.cleanUp() }
        let signedOut = try await ClaudeAuthStatus.isSignedOut(executable: fixture.executable.path, timeout: .seconds(1))
        XCTAssertFalse(signedOut)
    }

    private struct Fixture {
        let directory: URL
        var executable: URL { directory.appendingPathComponent("claude") }

        init(script: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeAuthStatusTests.\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }
}
