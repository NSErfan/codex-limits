import Foundation

/// Reads the signed-in account's Copilot allowance through the GitHub CLI, so
/// the app reuses that CLI's sign-in without handling a GitHub token itself.
enum CopilotUsageCommand {
    struct Response: Equatable, Sendable {
        let statusCode: Int
        let body: Data
    }

    /// The GitHub CLI's exit status when no account is signed in.
    private static let authenticationRequiredStatus: Int32 = 4

    static func executable() throws -> String {
        guard let path = ProviderExecutable.path(for: .copilot) else { throw CopilotClientError.cliNotFound }
        return path
    }

    static func run(
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath),
        timeout: Duration = .seconds(20),
        maximumOutputBytes: Int = 1_024 * 1_024
    ) async throws -> Response {
        let output: BoundedCommand.Output
        do {
            output = try await BoundedCommand.run(
                executable: executable,
                // --include prefixes the HTTP status, so failures are classified without parsing gh's error text.
                arguments: ["api", "--include", "--method", "GET", "copilot_internal/user"],
                environment: spawnEnvironment(environment, executable: executable),
                workingDirectory: workingDirectory,
                timeout: timeout,
                maximumOutputBytes: maximumOutputBytes
            )
        } catch let failure as BoundedCommand.Failure {
            switch failure {
            case .launchFailed: throw CopilotClientError.cliNotFound
            case .timedOut: throw CopilotClientError.timedOut
            case .outputLimitExceeded: throw CopilotClientError.invalidResponse
            case .readFailed: throw CopilotClientError.requestFailed
            }
        }
        // gh also exits unsuccessfully for HTTP errors; their status decides the outcome.
        if let response = response(from: output.standardOutput) { return response }
        if output.terminationStatus == authenticationRequiredStatus { throw CopilotClientError.credentialsMissing }
        throw output.terminationStatus == 0 ? CopilotClientError.invalidResponse : CopilotClientError.requestFailed
    }

    /// Splits `gh api --include` output into the HTTP status and the body that
    /// follows the first blank line after the headers.
    static func response(from output: Data) -> Response? {
        let newline = UInt8(ascii: "\n")
        let carriageReturn = UInt8(ascii: "\r")
        guard let statusEnd = output.firstIndex(of: newline) else { return nil }
        let statusFields = String(decoding: output[..<statusEnd], as: UTF8.self)
            .split(whereSeparator: \.isWhitespace)
        guard statusFields.count >= 2, statusFields[0].hasPrefix("HTTP/"),
              let statusCode = Int(statusFields[1]) else { return nil }
        var lineStart = output.index(after: statusEnd)
        while lineStart < output.endIndex {
            let lineEnd = output[lineStart...].firstIndex(of: newline) ?? output.endIndex
            let next = lineEnd < output.endIndex ? output.index(after: lineEnd) : lineEnd
            if output[lineStart ..< lineEnd].allSatisfy({ $0 == carriageReturn }) {
                return Response(statusCode: statusCode, body: Data(output[next...]))
            }
            lineStart = next
        }
        return nil
    }

    static func spawnEnvironment(_ environment: [String: String], executable: String) -> [String: String] {
        // Token variables are excluded so the CLI's saved sign-in, which Sign in manages, decides the account.
        let allowed: Set<String> = [
            "HOME", "USER", "LOGNAME", "PATH", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TZ",
            "GH_HOST", "GH_CONFIG_DIR", "XDG_CONFIG_HOME",
            "HTTPS_PROXY", "HTTP_PROXY", "ALL_PROXY", "NO_PROXY"
        ]
        var result = environment.filter { allowed.contains($0.key) }
        let directory = URL(fileURLWithPath: executable).deletingLastPathComponent().path
        result["PATH"] = directory + ":" + (result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
        result["GH_PROMPT_DISABLED"] = "1"
        result["GH_NO_UPDATE_NOTIFIER"] = "1"
        return result
    }
}
