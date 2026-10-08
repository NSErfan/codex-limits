import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

final class ProviderLoginTests: XCTestCase {
    func testLoginCommandPreservesProfileAndTreatsPathsAsLiteralShellArguments() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude's $(printf unwanted) `printf other`")
        try "#!/bin/sh\nprintf '%s\\n' \"$CLAUDE_CONFIG_DIR\" \"$CLAUDE_SECURESTORAGE_CONFIG_DIR\" \"$@\"\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let profile = "/Users/test's profile/$(printf should-not-run)"
        let keychainProfile = "/Users/another profile/`printf should-not-run`"
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", ProviderLogin.command(for: .claude, executable: executable.path, environment: [
            "CLAUDE_CONFIG_DIR": profile,
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": keychainProfile,
            "CODEX_HOME": "/irrelevant/profile",
            "ANTHROPIC_API_KEY": "must-not-be-serialized"
        ])]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(result, "\(profile)\n\(keychainProfile)\nauth\nlogin\n--claudeai\n")
        XCTAssertFalse(process.arguments![1].contains("must-not-be-serialized"))
        XCTAssertFalse(process.arguments![1].contains("CODEX_HOME"))
    }

    func testCodexLoginPreservesOnlyCodexProfile() {
        XCTAssertEqual(
            ProviderLogin.command(for: .codex, executable: "/opt/homebrew/bin/codex", environment: [
                "CODEX_HOME": "/Users/test profile/.codex",
                "CLAUDE_CONFIG_DIR": "/unused"
            ]),
            "'/usr/bin/env' 'CODEX_HOME=/Users/test profile/.codex' '/opt/homebrew/bin/codex' 'login'"
        )
    }

    func testCopilotLoginUsesGitHubCLIProfileWithoutInheritedTokens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("gh")
        try """
        #!/bin/sh
        printf '%s\\n' "${GH_CONFIG_DIR-unset}" "${XDG_CONFIG_HOME-unset}" "${GH_HOST-unset}" \\
            "${GH_TOKEN-unset}" "${GITHUB_TOKEN-unset}" "$@"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", ProviderLogin.command(for: .copilot, executable: executable.path, environment: [
            "GH_CONFIG_DIR": "/Users/test profile/gh",
            "CLAUDE_CONFIG_DIR": "/unused"
        ])]
        process.environment = ["XDG_CONFIG_HOME": "/wrong/config", "GH_HOST": "wrong.example.test",
                               "GH_TOKEN": "shell-token", "GITHUB_TOKEN": "shell-token"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(
            String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self),
            "/Users/test profile/gh\nunset\nunset\nunset\nunset\nauth\nlogin\n--web\n--hostname\ngithub.com\n"
        )
        XCTAssertFalse(process.arguments![1].contains("CLAUDE_CONFIG_DIR"))
    }

    func testCopilotLoginUsesTheAppsGitHubHost() {
        XCTAssertEqual(
            ProviderLogin.command(for: .copilot, executable: "/opt/homebrew/bin/gh", environment: [
                "GH_HOST": "octocorp.ghe.com"
            ]),
            "'/usr/bin/env' '-u' 'GH_CONFIG_DIR' '-u' 'XDG_CONFIG_HOME' '-u' 'GH_TOKEN' '-u' 'GITHUB_TOKEN' "
                + "'GH_HOST=octocorp.ghe.com' '/opt/homebrew/bin/gh' 'auth' 'login' '--web' '--hostname' 'octocorp.ghe.com'"
        )
        XCTAssertEqual(ProviderLogin.installationURL(for: .copilot).host, "cli.github.com")
    }

    func testLoginDoesNotInheritAProfileAbsentFromTheAppEnvironment() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executable = directory.appendingPathComponent("claude")
        try "#!/bin/sh\nprintf '%s\\n' \"${CLAUDE_CONFIG_DIR-unset}\" \"${CLAUDE_SECURESTORAGE_CONFIG_DIR-unset}\"\n"
            .write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let output = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", ProviderLogin.command(for: .claude, executable: executable.path, environment: [:])]
        process.environment = ["CLAUDE_CONFIG_DIR": "/wrong/profile", "CLAUDE_SECURESTORAGE_CONFIG_DIR": "/wrong/keychain"]
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertEqual(String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self), "unset\nunset\n")
    }

    func testExecutableDiscoverySkipsRelativePathsAndFindsCustomInstallation() {
        var checked: [String] = []
        let path = ProviderExecutable.path(
            for: .claude, environment: ["PATH": "relative:.:/custom/bin"],
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { path in
            checked.append(path)
            return path == "/custom/bin/claude"
        }
        XCTAssertEqual(path, "/custom/bin/claude")
        XCTAssertTrue(checked.allSatisfy { $0.hasPrefix("/") })
        XCTAssertTrue(checked.contains("/Users/test/.local/bin/claude"))
    }
}
