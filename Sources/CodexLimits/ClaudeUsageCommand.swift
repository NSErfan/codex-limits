import Foundation

enum ClaudeUsageCommand {
    static func executable() throws -> String {
        guard let path = ProviderExecutable.path(for: .claude) else { throw ClaudeClientError.cliNotFound }
        return path
    }

    static func run(
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        timeout: Duration = .seconds(25),
        maximumOutputBytes: Int = 2 * 1_024 * 1_024
    ) async throws -> Data {
        let output: BoundedCommand.Output
        do {
            // /usage is a local command. Zero turns also prevents inference if a future CLI stops recognizing it.
            // Keep relative profile paths literal: changing them to absolute paths changes the CLI's credential namespace.
            output = try await BoundedCommand.run(
                executable: executable,
                arguments: [
                    "--safe-mode", "--strict-mcp-config", "--tools", "",
                    "--settings", #"{"remoteControlAtStartup":false}"#,
                    "--no-session-persistence", "--max-turns", "0",
                    "--verbose", "--output-format", "stream-json", "--print", "/usage"
                ],
                environment: spawnEnvironment(environment, executable: executable),
                workingDirectory: workingDirectory,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
        } catch let failure as BoundedCommand.Failure {
            switch failure {
            case .launchFailed: throw ClaudeClientError.cliNotFound
            case .timedOut: throw ClaudeClientError.timedOut
            case .outputLimitExceeded: throw ClaudeClientError.invalidResponse
            case .readFailed: throw ClaudeClientError.commandFailed
            }
        }
        guard output.terminationStatus == 0 else { throw ClaudeClientError.commandFailed }
        return output.standardOutput
    }

    static func spawnEnvironment(_ environment: [String: String], executable: String) -> [String: String] {
        let allowed: Set<String> = [
            "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
            "CLAUDE_CONFIG_DIR", "CLAUDE_SECURESTORAGE_CONFIG_DIR",
            "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY", "NODE_EXTRA_CA_CERTS"
        ]
        var result = environment.filter { allowed.contains($0.key) }
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        result["PATH"] = directory + ":" + (result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        return result
    }
}
