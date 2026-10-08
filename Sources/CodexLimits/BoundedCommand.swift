import Darwin
import Foundation

/// Runs a non-interactive command with a deadline and an output cap, and
/// always terminates it on timeout, cancellation, or excessive output.
enum BoundedCommand {
    struct Output: Sendable {
        let terminationStatus: Int32
        let standardOutput: Data
    }

    enum Failure: Error, Equatable {
        case launchFailed
        case timedOut
        case outputLimitExceeded
        case readFailed
    }

    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        timeout: Duration,
        maximumOutputBytes: Int
    ) async throws -> Output {
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
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = workingDirectory
        // Some CLIs read inherited stdin as extra input unless it is explicitly closed.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw Failure.launchFailed }
        try output.fileHandleForWriting.close()
        let data = try await collectOutput(output.fileHandleForReading, process: process,
                                           timeout: timeout, maximumBytes: maximumOutputBytes)
        return Output(terminationStatus: process.terminationStatus, standardOutput: data)
    }

    private static func collectOutput(
        _ handle: FileHandle, process: Process, timeout: Duration, maximumBytes: Int
    ) async throws -> Data {
        let descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
            throw Failure.readFailed
        }
        let deadline = ContinuousClock.now.advanced(by: timeout)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        var reachedEnd = false
        while !reachedEnd || process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw Failure.timedOut }
            let count = read(descriptor, &buffer, buffer.count)
            if count > 0 {
                guard count <= maximumBytes - data.count else { throw Failure.outputLimitExceeded }
                data.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                reachedEnd = true
            } else if errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR {
                throw Failure.readFailed
            }
            if count <= 0 { try await Task.sleep(for: .milliseconds(10)) }
        }
        return data
    }
}
