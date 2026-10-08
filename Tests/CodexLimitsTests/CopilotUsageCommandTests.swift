import Darwin
import XCTest
@testable import CodexLimits

final class CopilotUsageCommandTests: XCTestCase {
    func testIncludedResponseSplitsStatusFromBodyAcrossMixedLineEndings() throws {
        let output = Data("HTTP/2.0 200 OK\nContent-Type: application/json\r\nX-GitHub-Request-Id: ABC\r\n\r\n{\"login\":\"octocat\"}\n".utf8)

        let response = try XCTUnwrap(CopilotUsageCommand.response(from: output))

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "{\"login\":\"octocat\"}\n")
    }

    func testOutputWithoutAnHTTPStatusLineIsNotAResponse() {
        XCTAssertNil(CopilotUsageCommand.response(from: Data()))
        XCTAssertNil(CopilotUsageCommand.response(from: Data("{\"login\":\"octocat\"}\n".utf8)))
        XCTAssertNil(CopilotUsageCommand.response(from: Data("HTTP/2.0 200 OK\nContent-Type: application/json\n".utf8)))
    }

    func testInvocationOnlyReadsTheCopilotUserEndpoint() async throws {
        let fixture = try Fixture(script: #"printf 'HTTP/2.0 200 OK\n\n'; printf '%s\0' "$@""#)
        defer { fixture.cleanUp() }

        let response = try await CopilotUsageCommand.run(executable: fixture.executable.path)

        let arguments = String(decoding: response.body, as: UTF8.self).components(separatedBy: "\0").dropLast()
        XCTAssertEqual(Array(arguments), ["api", "--include", "--method", "GET", "copilot_internal/user"])
    }

    func testHTTPErrorsAreReturnedEvenThoughTheCLIExitsUnsuccessfully() async throws {
        let fixture = try Fixture(script: #"printf 'HTTP/2.0 401 Unauthorized\r\n\r\n{"message":"Bad credentials"}'; exit 1"#)
        defer { fixture.cleanUp() }

        let response = try await CopilotUsageCommand.run(executable: fixture.executable.path)

        XCTAssertEqual(response.statusCode, 401)
    }

    func testSignedOutCLIRequiresLogin() async throws {
        let fixture = try Fixture(script: "echo 'To get started with GitHub CLI, please run:  gh auth login' >&2\nexit 4")
        defer { fixture.cleanUp() }

        await assertRun(fixture, throws: .credentialsMissing)
    }

    func testFailureWithoutAnHTTPResponseIsARetryableRequestFailure() async throws {
        let fixture = try Fixture(script: "echo fixture-secret\necho fixture-secret >&2\nexit 1")
        defer { fixture.cleanUp() }

        await assertRun(fixture, throws: .requestFailed)
        XCTAssertTrue(CopilotClientError.requestFailed.shouldRetryAutomatically)
        XCTAssertFalse(CopilotClientError.requestFailed.localizedDescription.contains("fixture-secret"))
    }

    func testEnvironmentKeepsGitHubProfileButExcludesTokensAndDisablesPrompts() {
        let environment = CopilotUsageCommand.spawnEnvironment([
            "HOME": "/fixture", "PATH": "/usr/bin:/bin", "GH_CONFIG_DIR": "/fixture/gh", "GH_HOST": "github.com",
            "XDG_CONFIG_HOME": "/fixture/config", "HTTPS_PROXY": "https://proxy.example.test",
            "GH_TOKEN": "unrelated-token", "GITHUB_TOKEN": "unrelated-token", "GH_ENTERPRISE_TOKEN": "unrelated-token",
            "GH_DEBUG": "api", "NODE_OPTIONS": "--require=/untrusted.js"
        ], executable: "/fixture/bin/gh")

        XCTAssertEqual(environment, [
            "HOME": "/fixture", "PATH": "/fixture/bin:/usr/bin:/bin", "GH_CONFIG_DIR": "/fixture/gh", "GH_HOST": "github.com",
            "XDG_CONFIG_HOME": "/fixture/config", "HTTPS_PROXY": "https://proxy.example.test",
            "GH_PROMPT_DISABLED": "1", "GH_NO_UPDATE_NOTIFIER": "1"
        ])
    }

    func testMissingExecutableAsksForTheGitHubCLI() async {
        do {
            _ = try await CopilotUsageCommand.run(executable: "/missing/gh")
            XCTFail("Expected missing CLI")
        } catch {
            XCTAssertEqual(error as? CopilotClientError, .cliNotFound)
            XCTAssertTrue((error as? CopilotClientError)?.requiresLogin == true)
        }
    }

    func testTimeoutTerminatesAndReapsCommand() async throws {
        let fixture = try Fixture(script: "echo $$ > pid\nwhile :; do :; done")
        defer { fixture.cleanUp() }
        do {
            _ = try await CopilotUsageCommand.run(executable: fixture.executable.path,
                                                  workingDirectory: fixture.directory, timeout: .seconds(1))
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? CopilotClientError, .timedOut) }
        try await fixture.assertStopped()
    }

    func testExecutableDiscoveryFindsTheGitHubCLIRatherThanTheCopilotCLI() {
        let path = ProviderExecutable.path(
            for: .copilot, environment: ["PATH": "/custom/bin"],
            homeDirectory: URL(fileURLWithPath: "/Users/test")
        ) { ["/custom/bin/gh", "/custom/bin/copilot"].contains($0) }
        XCTAssertEqual(path, "/custom/bin/gh")
    }

    private func assertRun(
        _ fixture: Fixture, throws expected: CopilotClientError,
        file: StaticString = #filePath, line: UInt = #line
    ) async {
        do {
            _ = try await CopilotUsageCommand.run(executable: fixture.executable.path)
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? CopilotClientError, expected, file: file, line: line)
        }
    }

    private struct Fixture: Sendable {
        let directory: URL
        var executable: URL { directory.appendingPathComponent("gh") }

        init(script: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("CopilotUsageCommandTests.\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(("#!/bin/sh\n" + script + "\n").utf8).write(to: executable)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        }

        func assertStopped(file: StaticString = #filePath, line: UInt = #line) async throws {
            let pid = try XCTUnwrap(Int32(String(contentsOf: directory.appendingPathComponent("pid"))
                .trimmingCharacters(in: .whitespacesAndNewlines)), file: file, line: line)
            for _ in 0 ..< 100 {
                if kill(pid, 0) == -1 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(kill(pid, 0), -1, file: file, line: line)
            XCTAssertEqual(errno, ESRCH, file: file, line: line)
        }

        func cleanUp() { try? FileManager.default.removeItem(at: directory) }
    }
}
