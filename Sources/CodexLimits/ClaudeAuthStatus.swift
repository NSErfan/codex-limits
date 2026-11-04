import Foundation

/// Reads the Claude Code CLI's saved sign-in state, which `/usage` doesn't report:
/// a signed-out CLI answers it with local session costs instead of subscription usage.
enum ClaudeAuthStatus {
    /// True only when the CLI positively reports that no sign-in is usable.
    /// Missing, failed, or unrecognized status checks never count as signed out.
    static func isSignedOut(
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        timeout: Duration = .seconds(10),
        maximumOutputBytes: Int = 64 * 1_024
    ) async throws -> Bool {
        let output: BoundedCommand.Output
        do {
            output = try await BoundedCommand.run(
                executable: executable,
                arguments: ["auth", "status", "--json"],
                environment: ClaudeUsageCommand.spawnEnvironment(environment, executable: executable),
                workingDirectory: workingDirectory,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
        } catch is BoundedCommand.Failure {
            return false
        }
        // The CLI also exits unsuccessfully when signed out, so its JSON decides the state.
        guard let status = try? JSONDecoder().decode(Status.self, from: output.standardOutput) else { return false }
        return !status.loggedIn
    }

    private struct Status: Decodable {
        let loggedIn: Bool
    }
}
