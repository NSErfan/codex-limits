import Darwin
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
        try Task.checkCancellation()
        let process = Process()
        let output = Pipe()
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
        }
        configure(process, output: output, executable: executable,
                  environment: environment, workingDirectory: workingDirectory)
        do { try process.run() } catch { throw ClaudeClientError.cliNotFound }
        try output.fileHandleForWriting.close()
        let data = try await collectOutput(output.fileHandleForReading, process: process,
                                           timeout: timeout, maximumBytes: maximumOutputBytes)
        guard process.terminationStatus == 0 else { throw ClaudeClientError.commandFailed }
        return data
    }

    private static func configure(
        _ process: Process, output: Pipe, executable: String,
        environment: [String: String], workingDirectory: URL
    ) {
        process.executableURL = URL(fileURLWithPath: executable)
        // /usage is a local command. Zero turns also prevents inference if a future CLI stops recognizing it.
        process.arguments = [
            "--safe-mode", "--strict-mcp-config", "--tools", "",
            "--settings", #"{"remoteControlAtStartup":false}"#,
            "--no-session-persistence", "--max-turns", "0",
            "--verbose", "--output-format", "stream-json", "--print", "/usage"
        ]
        process.environment = spawnEnvironment(environment, executable: executable)
        // Keep relative profile paths literal: changing them to absolute paths changes the CLI's credential namespace.
        process.currentDirectoryURL = workingDirectory
        // Print mode appends inherited stdin to the command's arguments unless explicitly closed.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
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

    private static func collectOutput(
        _ handle: FileHandle, process: Process, timeout: Duration, maximumBytes: Int
    ) async throws -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw ClaudeClientError.commandFailed
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var reachedEnd = false
        while !reachedEnd || process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw ClaudeClientError.timedOut }
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maximumBytes - data.count else { throw ClaudeClientError.invalidResponse }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                reachedEnd = true
            } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                throw ClaudeClientError.commandFailed
            }
            if count <= 0 { try await Task.sleep(for: .milliseconds(10)) }
        }
        return data
    }
}
