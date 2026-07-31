import Darwin
import Foundation

enum CodexClient {
    private static let retryDelayNanoseconds: UInt64 = 250_000_000
    private static let timeoutNanoseconds: UInt64 = 15_000_000_000
    private static let executablePaths = [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    static func fetch() async throws -> UsageSnapshot {
        try await fetch(
            executablePaths: executablePaths,
            isExecutable: FileManager.default.isExecutableFile(atPath:),
            retryDelayNanoseconds: retryDelayNanoseconds,
            timeoutNanoseconds: timeoutNanoseconds,
            makeConnection: makeLiveConnection(using:)
        )
    }

    static func fetch(
        executablePaths: [String],
        isExecutable: (String) -> Bool,
        retryDelayNanoseconds: UInt64,
        timeoutNanoseconds: UInt64,
        makeConnection: (String) throws -> CodexAppServerConnection
    ) async throws -> UsageSnapshot {
        guard let executable = executablePaths.first(where: isExecutable) else {
            throw CodexClientError.cliNotFound
        }

        return try await retryOnceAfterFailure(
            delayNanoseconds: retryDelayNanoseconds
        ) {
            try await fetchOnce(
                using: executable,
                timeoutNanoseconds: timeoutNanoseconds,
                makeConnection: makeConnection
            )
        }
    }

    static func retryOnceAfterFailure<Result>(
        delayNanoseconds: UInt64 = 250_000_000,
        operation: () async throws -> Result
    ) async throws -> Result {
        do {
            return try await operation()
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            try Task.checkCancellation()
            if delayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: delayNanoseconds)
            }
            return try await operation()
        }
    }

    private static func fetchOnce(
        using executable: String,
        timeoutNanoseconds: UInt64,
        makeConnection: (String) throws -> CodexAppServerConnection
    ) async throws -> UsageSnapshot {
        try Task.checkCancellation()
        let connection = try makeConnection(executable)
        defer { connection.stop() }
        try connection.start()
        try Task.checkCancellation()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        try write(
            #"{"id":\#(RequestID.initialize.rawValue),"method":"initialize","params":{"clientInfo":{"name":"codex-limits","title":"Codex Limits","version":"\#(version)"},"capabilities":{"experimentalApi":true}}}"#,
            to: connection.input
        )
        let fetchedAt = Date()
        return try await withTaskCancellationHandler {
            try await withThrowingTaskGroup(of: FetchAttemptEvent.self) { group in
                group.addTask {
                    .snapshot(
                        try await readSnapshot(
                            from: connection,
                            fetchedAt: fetchedAt
                        )
                    )
                }
                group.addTask {
                    try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    return .timedOut
                }
                guard let first = try await group.next() else {
                    throw CodexClientError.invalidResponse
                }
                switch first {
                case let .snapshot(snapshot):
                    group.cancelAll()
                    return snapshot
                case .timedOut:
                    connection.stop()
                    group.cancelAll()
                    throw CodexClientError.timedOut
                }
            }
        } onCancel: {
            connection.stop()
        }
    }

    private static func makeLiveConnection(
        using executable: String
    ) -> CodexAppServerConnection {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--stdio"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        return CodexAppServerConnection(
            input: input.fileHandleForWriting,
            output: output.fileHandleForReading,
            start: { try process.run() },
            stop: {
                try? input.fileHandleForWriting.close()
                if process.isRunning {
                    process.terminate()
                }
                try? output.fileHandleForWriting.close()
            }
        )
    }

    static func decode(
        rateLimitsResponse: Data,
        usageResponse: Data?,
        fetchedAt: Date
    ) throws -> UsageSnapshot {
        let decoder = JSONDecoder()
        guard let rateResult = try decoder.decode(
            RPCResponse<RateLimitsResult>.self,
            from: rateLimitsResponse
        ).result else {
            throw CodexClientError.invalidResponse
        }
        let usageResult: UsageResult?
        if let usageResponse {
            guard let result = try decoder.decode(
                RPCResponse<UsageResult>.self,
                from: usageResponse
            ).result else {
                throw CodexClientError.invalidResponse
            }
            usageResult = result
        } else {
            usageResult = nil
        }

        let snapshots = rateResult.rateLimitsByLimitId ?? ["codex": rateResult.rateLimits]
        let mainSnapshot = snapshots["codex"] ?? rateResult.rateLimits
        let mainWindows = windows(from: mainSnapshot)
        guard let mainWindow = mainWindows.min(by: {
            $0.remainingPercent < $1.remainingPercent
        }) else {
            throw CodexClientError.mainLimitMissing
        }

        let extraMainWindows = mainWindows
            .filter { $0 != mainWindow }
            .map {
                LimitReading(limitId: "codex", name: windowName($0.durationMinutes), window: $0)
            }
        let otherLimits = snapshots
            .filter { $0.key != "codex" }
            .compactMap { id, snapshot -> LimitReading? in
                guard let window = windows(from: snapshot).min(by: {
                    $0.remainingPercent < $1.remainingPercent
                }) else { return nil }
                return LimitReading(
                    limitId: id,
                    name: snapshot.limitName ?? id,
                    window: window
                )
            }
        let others = (extraMainWindows + otherLimits)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let tokenHistory = (usageResult?.dailyUsageBuckets ?? []).compactMap { bucket -> TokenDay? in
            guard let date = dateFormatter.date(from: bucket.startDate) else { return nil }
            return TokenDay(date: date, tokens: bucket.tokens)
        }

        return UsageSnapshot(
            mainLimit: LimitReading(limitId: "codex", name: "Codex", window: mainWindow),
            otherLimits: others,
            tokenHistory: tokenHistory,
            resetCredits: resetCredits(from: rateResult.rateLimitResetCredits, fetchedAt: fetchedAt),
            fetchedAt: fetchedAt
        )
    }

    private static func resetCredits(
        from payload: ResetCredits?,
        fetchedAt: Date
    ) -> [ResetCredit] {
        guard let payload else { return [] }
        guard let credits = payload.credits else {
            // Older CLI versions report only a count.
            return (0 ..< max(payload.availableCount ?? 0, 0)).map {
                ResetCredit(id: "unknown-\($0)", title: nil, expiresAt: nil)
            }
        }
        return credits
            .filter { credit in
                credit.status == "available"
                    && credit.expiresAt.map {
                        Date(timeIntervalSince1970: TimeInterval($0)) > fetchedAt
                    } ?? true
            }
            .map {
                ResetCredit(
                    id: $0.id,
                    title: $0.title,
                    expiresAt: $0.expiresAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
                )
            }
            .sorted {
                switch ($0.expiresAt, $1.expiresAt) {
                case let (first?, second?) where first != second: first < second
                case (.some, .none): true
                case (.none, .some): false
                default: $0.id < $1.id
                }
            }
    }

    private static func windows(from snapshot: RateLimitSnapshot) -> [UsageWindow] {
        [snapshot.primary, snapshot.secondary].compactMap { window in
            guard let window,
                  let resetsAt = window.resetsAt,
                  let duration = window.windowDurationMins else { return nil }
            return UsageWindow(
                remainingPercent: min(max(100 - window.usedPercent, 0), 100),
                resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt)),
                durationMinutes: duration
            )
        }
    }

    private static func windowName(_ minutes: Int) -> String {
        if minutes == 10_080 { return "Weekly window" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)-hour window" }
        return "Additional window"
    }

    private static func write(_ message: String, to handle: FileHandle) throws {
        try handle.write(contentsOf: Data((message + "\n").utf8))
    }

    static func readSnapshot(
        from output: FileHandle,
        writingTo input: FileHandle,
        fetchedAt: Date
    ) async throws -> UsageSnapshot {
        let connection = CodexAppServerConnection(
            input: input,
            output: output,
            start: {},
            stop: {}
        )
        return try await readSnapshot(
            from: connection,
            fetchedAt: fetchedAt
        )
    }

    private static func readSnapshot(
        from connection: CodexAppServerConnection,
        fetchedAt: Date
    ) async throws -> UsageSnapshot {
        var rateLimitsResponse: Data?
        var usageResponse: Data?
        var usageRequestFinished = false

        while let data = try await connection.readLine() {
            try Task.checkCancellation()
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rawID = object["id"] as? Int,
                  let id = RequestID(rawValue: rawID) else { continue }

            if object.keys.contains("error") {
                guard (try? JSONDecoder().decode(RPCErrorEnvelope.self, from: data)) != nil else {
                    throw CodexClientError.invalidResponse
                }
                switch id {
                case .initialize, .rateLimits:
                    throw CodexClientError.invalidResponse
                case .usage:
                    usageRequestFinished = true
                }
            } else {
                switch id {
                case .initialize:
                    try write(
                        #"{"method":"initialized"}"#,
                        to: connection.input
                    )
                    try write(
                        #"{"id":\#(RequestID.rateLimits.rawValue),"method":"account/rateLimits/read"}"#,
                        to: connection.input
                    )
                    try write(
                        #"{"id":\#(RequestID.usage.rawValue),"method":"account/usage/read"}"#,
                        to: connection.input
                    )
                case .rateLimits:
                    rateLimitsResponse = data
                case .usage:
                    usageResponse = data
                    usageRequestFinished = true
                }
            }

            if let rateLimitsResponse, usageRequestFinished {
                return try decode(
                    rateLimitsResponse: rateLimitsResponse,
                    usageResponse: usageResponse,
                    fetchedAt: fetchedAt
                )
            }
        }
        throw CodexClientError.invalidResponse
    }

    private enum FetchAttemptEvent: Sendable {
        case snapshot(UsageSnapshot)
        case timedOut
    }
}

final class CodexAppServerConnection: @unchecked Sendable {
    private static let defaultMaximumLineBytes = 16 * 1_024 * 1_024

    let input: FileHandle

    private let startOperation: () throws -> Void
    private let stopOperation: () -> Void
    private let outputDescriptor: Int32
    private let maximumLineBytes: Int
    private let lock = NSLock()
    private var didStop = false
    private var bufferedOutput = Data()

    init(
        input: FileHandle,
        output: FileHandle,
        maximumLineBytes: Int = defaultMaximumLineBytes,
        start: @escaping () throws -> Void,
        stop: @escaping () -> Void
    ) {
        self.input = input
        outputDescriptor = Self.duplicateNonblockingDescriptor(
            output.fileDescriptor
        )
        self.maximumLineBytes = max(maximumLineBytes, 1)
        startOperation = start
        stopOperation = stop
    }

    deinit {
        if outputDescriptor >= 0 {
            Darwin.close(outputDescriptor)
        }
    }

    func start() throws {
        try startOperation()
    }

    func stop() {
        lock.lock()
        let shouldStop = !didStop
        didStop = true
        lock.unlock()

        if shouldStop {
            stopOperation()
        }
    }

    func readLine() async throws -> Data? {
        var searchedByteCount = 0
        while true {
            try Task.checkCancellation()
            guard !hasStopped else { return nil }
            let searchStart = bufferedOutput.index(
                bufferedOutput.startIndex,
                offsetBy: min(searchedByteCount, bufferedOutput.count)
            )
            if let newline = bufferedOutput[searchStart...].firstIndex(
                of: 0x0A
            ) {
                let lineByteCount = bufferedOutput.distance(
                    from: bufferedOutput.startIndex,
                    to: newline
                )
                guard lineByteCount <= maximumLineBytes else {
                    return closeOversizedLine()
                }
                let line = bufferedOutput[..<newline]
                bufferedOutput.removeSubrange(...newline)
                return Data(line)
            }
            searchedByteCount = bufferedOutput.count
            if bufferedOutput.count > maximumLineBytes {
                return closeOversizedLine()
            }
            switch Self.readChunk(from: outputDescriptor) {
            case let .data(chunk):
                bufferedOutput.append(chunk)
            case .retry:
                try await Task.sleep(nanoseconds: 5_000_000)
            case .endOfFile:
                guard !bufferedOutput.isEmpty else { return nil }
                defer { bufferedOutput.removeAll() }
                return bufferedOutput
            }
        }
    }

    private var hasStopped: Bool {
        lock.lock()
        defer { lock.unlock() }
        return didStop
    }

    private func closeOversizedLine() -> Data? {
        bufferedOutput.removeAll()
        stop()
        return nil
    }

    private static func duplicateNonblockingDescriptor(
        _ descriptor: Int32
    ) -> Int32 {
        let duplicate = Darwin.dup(descriptor)
        guard duplicate >= 0 else { return -1 }
        let flags = Darwin.fcntl(duplicate, F_GETFL)
        guard flags >= 0,
              Darwin.fcntl(duplicate, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            Darwin.close(duplicate)
            return -1
        }
        return duplicate
    }

    private static func readChunk(from descriptor: Int32) -> ReadChunkResult {
        guard descriptor >= 0 else { return .endOfFile }
        var data = Data(count: 64 * 1_024)
        let count = data.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, $0.count)
        }
        if count > 0 {
            data.count = count
            return .data(data)
        }
        if count == 0 {
            return .endOfFile
        }
        if errno == EINTR || errno == EAGAIN || errno == EWOULDBLOCK {
            return .retry
        }
        return .endOfFile
    }

    private enum ReadChunkResult {
        case data(Data)
        case retry
        case endOfFile
    }
}

private enum RequestID: Int {
    case initialize = 1
    case rateLimits = 2
    case usage = 3
}

private struct RPCErrorEnvelope: Decodable {
    let error: RPCError
}

private struct RPCError: Decodable {
    let code: Double
    let message: String
}

private struct RPCResponse<Result: Decodable>: Decodable {
    let result: Result?
}

private struct RateLimitsResult: Decodable {
    let rateLimits: RateLimitSnapshot
    let rateLimitsByLimitId: [String: RateLimitSnapshot]?
    let rateLimitResetCredits: ResetCredits?
}

private struct ResetCredits: Decodable {
    let availableCount: Int?
    let credits: [ResetCreditPayload]?
}

private struct ResetCreditPayload: Decodable {
    let id: String
    let status: String?
    let expiresAt: Int64?
    let title: String?
}

private struct RateLimitSnapshot: Decodable {
    let limitId: String?
    let limitName: String?
    let primary: RateLimitWindow?
    let secondary: RateLimitWindow?
}

private struct RateLimitWindow: Decodable {
    let usedPercent: Double
    let windowDurationMins: Int?
    let resetsAt: Int64?
}

private struct UsageResult: Decodable {
    let dailyUsageBuckets: [TokenBucket]?
}

private struct TokenBucket: Decodable {
    let startDate: String
    let tokens: Int64
}
