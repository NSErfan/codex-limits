import Darwin
import XCTest
@testable import CodexLimits

final class ClaudeUsageCommandTests: XCTestCase {
    func testUsageInvocationCannotRunToolsOrModelTurnsOrSaveSession() async throws {
        let fixture = try Fixture(script: #"printf '%s\0' "$@""#)
        defer { fixture.cleanUp() }
        let data = try await ClaudeUsageCommand.run(executable: fixture.executable.path)
        let arguments = String(decoding: data, as: UTF8.self).components(separatedBy: "\0").dropLast()
        XCTAssertEqual(arguments.suffix(2), ["--print", "/usage"])
        for flag in ["--safe-mode", "--strict-mcp-config", "--no-session-persistence", "--verbose"] {
            XCTAssertTrue(arguments.contains(flag))
        }
        for (flag, value) in [("--max-turns", "0"), ("--tools", ""), ("--output-format", "stream-json"),
                              ("--settings", #"{"remoteControlAtStartup":false}"#)] {
            let index = try XCTUnwrap(arguments.firstIndex(of: flag))
            XCTAssertEqual(arguments[arguments.index(after: index)], value)
        }
    }

    func testCommandHasNoInheritedInputAndPreservesProfileWorkingDirectory() async throws {
        let fixture = try Fixture(script: "if IFS= read -r line; then exit 7; fi\npwd -P")
        defer { fixture.cleanUp() }
        let data = try await ClaudeUsageCommand.run(executable: fixture.executable.path, workingDirectory: fixture.directory)
        let path = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(URL(fileURLWithPath: path).resolvingSymlinksInPath(), fixture.directory.resolvingSymlinksInPath())
    }

    func testEnvironmentKeepsProfilesButExcludesAlternateAuthProvidersAndRuntimeInjection() {
        let environment = ClaudeUsageCommand.spawnEnvironment([
            "HOME": "/fixture", "PATH": "/usr/bin:/bin", "CLAUDE_CONFIG_DIR": "relative-profile",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "", "HTTPS_PROXY": "https://proxy.example.test",
            "ANTHROPIC_API_KEY": "unrelated-key", "ANTHROPIC_BASE_URL": "https://unrelated.example.test",
            "CLAUDE_CODE_OAUTH_TOKEN": "unrelated-login", "CLAUDE_CODE_USE_BEDROCK": "1",
            "NODE_OPTIONS": "--require=/untrusted.js", "CLAUDECODE": "1"
        ], executable: "/fixture/bin/claude")
        XCTAssertEqual(environment, [
            "HOME": "/fixture", "PATH": "/fixture/bin:/usr/bin:/bin", "CLAUDE_CONFIG_DIR": "relative-profile",
            "CLAUDE_SECURESTORAGE_CONFIG_DIR": "", "HTTPS_PROXY": "https://proxy.example.test"
        ])
    }

    func testFailedCommandDoesNotExposeItsOutput() async throws {
        let fixture = try Fixture(script: "echo fixture-secret\necho fixture-secret >&2\nexit 1")
        defer { fixture.cleanUp() }
        do {
            _ = try await ClaudeUsageCommand.run(executable: fixture.executable.path)
            XCTFail("Expected failure")
        } catch let error as ClaudeClientError {
            XCTAssertEqual(error, .commandFailed)
            XCTAssertFalse(error.localizedDescription.contains("fixture-secret"))
        }
    }

    func testMissingExecutableHasActionableError() async {
        do {
            _ = try await ClaudeUsageCommand.run(executable: "/missing/claude")
            XCTFail("Expected missing CLI")
        } catch { XCTAssertEqual(error as? ClaudeClientError, .cliNotFound) }
    }

    func testTimeoutTerminatesAndReapsCommand() async throws {
        let fixture = try Fixture(script: "echo $$ > pid\nwhile :; do :; done")
        defer { fixture.cleanUp() }
        do {
            _ = try await ClaudeUsageCommand.run(executable: fixture.executable.path,
                                                 workingDirectory: fixture.directory, timeout: .seconds(1))
            XCTFail("Expected timeout")
        } catch { XCTAssertEqual(error as? ClaudeClientError, .timedOut) }
        try await fixture.assertStopped()
    }

    func testCancellationTerminatesAndReapsCommand() async throws {
        let fixture = try Fixture(script: "echo $$ > pid\nwhile :; do :; done")
        defer { fixture.cleanUp() }
        let task = Task { try await ClaudeUsageCommand.run(executable: fixture.executable.path, workingDirectory: fixture.directory) }
        defer { task.cancel() }
        for _ in 0 ..< 100 {
            if FileManager.default.fileExists(atPath: fixture.directory.appendingPathComponent("pid").path) { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch { XCTFail("Expected CancellationError") }
        try await fixture.assertStopped()
    }

    func testOutputLimitStopsCommand() async throws {
        let fixture = try Fixture(script: "echo $$ > pid\nwhile :; do printf '0123456789'; done")
        defer { fixture.cleanUp() }
        do {
            _ = try await ClaudeUsageCommand.run(executable: fixture.executable.path,
                                                 workingDirectory: fixture.directory, maximumOutputBytes: 100)
            XCTFail("Expected bounded output")
        } catch { XCTAssertEqual(error as? ClaudeClientError, .invalidResponse) }
        try await fixture.assertStopped()
    }

    private struct Fixture: Sendable {
        let directory: URL
        var executable: URL { directory.appendingPathComponent("claude") }

        init(script: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent("ClaudeUsageCommandTests.\(UUID().uuidString)")
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
