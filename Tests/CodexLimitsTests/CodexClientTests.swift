import XCTest
@testable import CodexLimits

final class CodexClientTests: XCTestCase {
    func testEveryClientFailureHasAnActionableUserMessage() {
        let messages: [(CodexClientError, String)] = [
            (
                .cliNotFound,
                "Codex CLI was not found. Install it with Homebrew, sign in, and try again."
            ),
            (
                .invalidResponse,
                "Codex returned data this app could not read. Update Codex CLI and try again."
            ),
            (
                .mainLimitMissing,
                "Codex did not return a usable limit. Make sure Codex CLI is signed in."
            ),
            (
                .timedOut,
                "Codex took too long to respond. Try refreshing again."
            )
        ]

        for (error, message) in messages {
            XCTAssertEqual(error.localizedDescription, message)
        }
    }

    func testRetriesOneFailedFetchThenReturnsTheSecondResult() async throws {
        var attempts = 0

        let value: String = try await CodexClient.retryOnceAfterFailure(
            delayNanoseconds: 0
        ) {
            attempts += 1
            if attempts == 1 {
                throw CodexClientError.invalidResponse
            }
            return "recovered"
        }

        XCTAssertEqual(value, "recovered")
        XCTAssertEqual(attempts, 2)
    }

    func testStopsAfterTheSecondFailedFetch() async {
        var attempts = 0

        do {
            let _: String = try await CodexClient.retryOnceAfterFailure(
                delayNanoseconds: 0
            ) {
                attempts += 1
                throw CodexClientError.invalidResponse
            }
            XCTFail("Expected the second failure to be returned")
        } catch let error as CodexClientError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected invalidResponse, got \(error)")
        }

        XCTAssertEqual(attempts, 2)
    }

    func testDoesNotRetryCancellation() async {
        var attempts = 0

        do {
            let _: String = try await CodexClient.retryOnceAfterFailure(
                delayNanoseconds: 0
            ) {
                attempts += 1
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(attempts, 1)
    }

    func testCancellationDuringRetryDelayPreventsASecondAttempt() async {
        let probe = RetryAttemptProbe()
        let task = Task<String, Error> {
            try await CodexClient.retryOnceAfterFailure(
                delayNanoseconds: 5_000_000_000
            ) {
                try await probe.fail()
            }
        }
        await probe.waitUntilAttempted()

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        let attemptCount = await probe.attemptCount
        XCTAssertEqual(attemptCount, 1)
    }

    func testSuccessfulFetchUsesOneConnectionAndSendsTheCompleteHandshake() async throws {
        let server = AppServerFixture(behaviors: [.success])

        let result: UsageSnapshot
        do {
            result = try await fetchSnapshot(using: server)
        } catch {
            return XCTFail(
                "Fetch failed after requests \(server.requestMethods): \(error)"
            )
        }

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(server.startCount, 1)
        XCTAssertEqual(server.stopCount, 1)
        XCTAssertEqual(
            server.requestMethods,
            [
                "initialize",
                "initialized",
                "account/rateLimits/read",
                "account/usage/read"
            ]
        )
    }

    func testFetchUsesTheFirstAvailableExecutable() async throws {
        let server = AppServerFixture(behaviors: [.success])

        _ = try await fetchSnapshot(
            using: server,
            executablePaths: ["/missing/codex", "/available/codex"],
            isExecutable: { $0 == "/available/codex" }
        )

        XCTAssertEqual(server.executables, ["/available/codex"])
    }

    func testMissingExecutableDoesNotCreateAConnection() async {
        let server = AppServerFixture(behaviors: [.success])

        do {
            _ = try await fetchSnapshot(
                using: server,
                isExecutable: { _ in false }
            )
            XCTFail("Expected cliNotFound")
        } catch let error as CodexClientError {
            guard case .cliNotFound = error else {
                return XCTFail("Expected cliNotFound, got \(error)")
            }
        } catch {
            XCTFail("Expected cliNotFound, got \(error)")
        }

        XCTAssertEqual(server.connectionCount, 0)
        XCTAssertEqual(server.stopCount, 0)
    }

    func testProtocolFailureRetriesWithAFreshConnection() async throws {
        let server = AppServerFixture(
            behaviors: [.initializationError, .success]
        )

        let result = try await fetchSnapshot(using: server)

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(server.startCount, 2)
        XCTAssertEqual(server.stopCount, 2)
    }

    func testStartFailureIsCleanedUpBeforeRetrying() async throws {
        let server = AppServerFixture(behaviors: [.startFailure, .success])

        let result = try await fetchSnapshot(using: server)

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(server.startCount, 2)
        XCTAssertEqual(server.stopCount, 2)
    }

    func testEOFAndMalformedOutputRecoverOnAFreshConnection() async throws {
        for firstBehavior in [
            AppServerFixture.Behavior.endOfFile,
            .malformedOutput
        ] {
            let server = AppServerFixture(
                behaviors: [firstBehavior, .success]
            )

            let result = try await fetchSnapshot(using: server)

            XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
            XCTAssertEqual(server.connectionCount, 2)
            XCTAssertEqual(server.stopCount, 2)
        }
    }

    func testSecondProtocolFailureIsReturnedAndBothConnectionsAreStopped() async {
        let server = AppServerFixture(
            behaviors: [.initializationError, .rateLimitsError]
        )

        do {
            _ = try await fetchSnapshot(using: server)
            XCTFail("Expected invalidResponse")
        } catch let error as CodexClientError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
        } catch {
            XCTFail("Expected invalidResponse, got \(error)")
        }

        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(server.stopCount, 2)
    }

    func testTimeoutRetriesOnceThenReturnsTimedOut() async {
        let server = AppServerFixture(behaviors: [.stall, .stall])

        do {
            _ = try await fetchSnapshot(
                using: server,
                timeoutNanoseconds: 10_000_000
            )
            XCTFail("Expected timedOut")
        } catch let error as CodexClientError {
            guard case .timedOut = error else {
                return XCTFail("Expected timedOut, got \(error)")
            }
        } catch {
            XCTFail("Expected timedOut, got \(error)")
        }

        XCTAssertEqual(server.connectionCount, 2)
        XCTAssertEqual(server.stopCount, 2)
    }

    func testCancellationStopsAStalledConnectionWithoutRetrying() async {
        let server = AppServerFixture(behaviors: [.stall])
        let task = Task {
            try await fetchSnapshot(
                using: server,
                timeoutNanoseconds: 5_000_000_000
            )
        }
        while server.startCount == 0 {
            await Task.yield()
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(server.stopCount, 1)
    }

    func testUsageRPCFailureDoesNotTriggerAConnectionRetry() async throws {
        let server = AppServerFixture(behaviors: [.usageError])

        let result = try await fetchSnapshot(using: server)

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory, [])
        XCTAssertEqual(server.connectionCount, 1)
        XCTAssertEqual(server.stopCount, 1)
    }

    func testDecodesMainLimitOtherLimitsAndUsageHistory() throws {
        let rateLimits = Data(#"""
        {"id":2,"result":{
          "rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},
          "rateLimitsByLimitId":{
            "codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},
            "codex_example":{"limitId":"codex_example","limitName":"Example model","primary":{"usedPercent":0,"windowDurationMins":10080,"resetsAt":2100000}}
          },
          "rateLimitResetCredits":{"availableCount":3}
        }}
        """#.utf8)
        let usage = Data(#"""
        {"id":3,"result":{
          "dailyUsageBuckets":[
            {"startDate":"2001-01-01","tokens":1000},
            {"startDate":"2001-01-02","tokens":250}
          ]
        }}
        """#.utf8)
        let fetchedAt = Date(timeIntervalSince1970: 1_900_000)

        let result = try CodexClient.decode(
            rateLimitsResponse: rateLimits,
            usageResponse: usage,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.mainLimit.window.durationMinutes, 10_080)
        XCTAssertEqual(result.mainLimit.window.resetsAt, Date(timeIntervalSince1970: 2_000_000))
        XCTAssertEqual(result.otherLimits.map(\.name), ["Example model"])
        XCTAssertEqual(result.tokenHistory.map(\.tokens), [1_000, 250])
        XCTAssertEqual(result.resetCredits.count, 3)
        XCTAssertEqual(result.resetCredits.compactMap(\.expiresAt), [])
        XCTAssertEqual(result.fetchedAt, fetchedAt)
    }

    func testKeepsOnlyAvailableUnexpiredResetCreditsSortedByExpiry() throws {
        let rateLimits = Data(#"""
        {"id":2,"result":{
          "rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},
          "rateLimitResetCredits":{"availableCount":4,"credits":[
            {"id":"later","status":"available","expiresAt":2600000,"title":"Full reset"},
            {"id":"sooner","status":"available","expiresAt":2500000,"title":"Full reset"},
            {"id":"used","status":"used","expiresAt":2600000,"title":"Full reset"},
            {"id":"expired","status":"available","expiresAt":1000000,"title":"Full reset"},
            {"id":"open-ended","status":"available"}
          ]}
        }}
        """#.utf8)

        let result = try CodexClient.decode(
            rateLimitsResponse: rateLimits,
            usageResponse: nil,
            fetchedAt: Date(timeIntervalSince1970: 1_900_000)
        )

        XCTAssertEqual(result.resetCredits.map(\.id), ["sooner", "later", "open-ended"])
        XCTAssertEqual(
            result.resetCredits.first?.expiresAt,
            Date(timeIntervalSince1970: 2_500_000)
        )
        XCTAssertNil(result.resetCredits.last?.expiresAt)
    }

    func testUsageRPCErrorDoesNotDiscardRateLimits() async throws {
        let fetchedAt = Self.fetchedAt

        let result = try await readSnapshot(
            responses: [Self.usageErrorResponse, Self.rateLimitsResponse],
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory, [])
        XCTAssertEqual(result.fetchedAt, fetchedAt)
    }

    func testUsageRPCErrorAfterRateLimitsDoesNotDiscardRateLimits() async throws {
        let result = try await readSnapshot(
            responses: [Self.rateLimitsResponse, Self.usageErrorResponse],
            fetchedAt: Self.fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory, [])
        XCTAssertEqual(result.fetchedAt, Self.fetchedAt)
    }

    func testSuccessfulResponsesDecodeInEitherOrder() async throws {
        for responses in [
            [Self.rateLimitsResponse, Self.usageResponse],
            [Self.usageResponse, Self.rateLimitsResponse]
        ] {
            let result = try await readSnapshot(
                responses: responses,
                fetchedAt: Self.fetchedAt
            )

            XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
            XCTAssertEqual(result.tokenHistory.map(\.tokens), [1_000])
        }
    }

    func testProtocolNoiseAndUnknownRequestIDsAreIgnored() async throws {
        let result = try await readSnapshot(
            responses: [
                "not-json",
                #"{"method":"account/rateLimits/updated","params":{}}"#,
                #"{"id":99,"result":{"unexpected":true}}"#,
                Self.usageResponse,
                Self.rateLimitsResponse
            ],
            fetchedAt: Self.fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory.map(\.tokens), [1_000])
    }

    func testIncompleteProtocolStreamsRemainInvalid() async throws {
        let incompleteStreams = [
            [String](),
            [Self.rateLimitsResponse],
            [Self.usageResponse],
            [#"{"id":1,"result":{}}"#]
        ]

        for responses in incompleteStreams {
            try await assertInvalidResponse(responses: responses)
        }
    }

    func testFragmentedProtocolLineIsReassembled() async throws {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        let midpoint = Self.rateLimitsResponse.index(
            Self.rateLimitsResponse.startIndex,
            offsetBy: Self.rateLimitsResponse.count / 2
        )
        let firstHalf = String(Self.rateLimitsResponse[..<midpoint])
        let secondHalf = String(Self.rateLimitsResponse[midpoint...])
        let read = Task {
            try await CodexClient.readSnapshot(
                from: serverOutput.fileHandleForReading,
                writingTo: clientInput.fileHandleForWriting,
                fetchedAt: Self.fetchedAt
            )
        }

        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data(firstHalf.utf8)
        )
        await Task.yield()
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data(
                (secondHalf + "\n" + Self.usageResponse + "\n").utf8
            )
        )
        try serverOutput.fileHandleForWriting.close()

        let result = try await read.value

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory.map(\.tokens), [1_000])
    }

    func testProtocolLineLimitAcceptsBoundaryAndRejectsOversizedLine() async throws {
        let accepted = try await readBoundedLine("1234\n", maximumBytes: 4)

        XCTAssertEqual(accepted.line, Data("1234".utf8))
        XCTAssertEqual(accepted.stopCount, 0)

        let rejected = try await readBoundedLine("12345\n", maximumBytes: 4)

        XCTAssertNil(rejected.line)
        XCTAssertEqual(rejected.stopCount, 1)

        let rejectedAtEOF = try await readBoundedLine("12345", maximumBytes: 4)

        XCTAssertNil(rejectedAtEOF.line)
        XCTAssertEqual(rejectedAtEOF.stopCount, 1)
    }

    func testStoppingConnectionUnblocksReaderWithoutProducerEOF() async throws {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        var stopCount = 0
        let connection = CodexAppServerConnection(
            input: clientInput.fileHandleForWriting,
            output: serverOutput.fileHandleForReading,
            start: {},
            stop: { stopCount += 1 }
        )
        let read = Task {
            try await connection.readLine()
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        let safetyClose = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000)
                try serverOutput.fileHandleForWriting.close()
            } catch {
                // Cancellation means the reader stopped without producer EOF.
            }
        }

        let stoppedAt = Date()
        connection.stop()
        let line = try await read.value
        let stopLatency = Date().timeIntervalSince(stoppedAt)
        safetyClose.cancel()
        try? serverOutput.fileHandleForWriting.close()

        XCTAssertNil(line)
        XCTAssertEqual(stopCount, 1)
        XCTAssertLessThan(stopLatency, 0.5)
    }

    func testJSONEnvelopeSplitAcrossProtocolLinesRemainsInvalid() async throws {
        let midpoint = Self.rateLimitsResponse.index(
            Self.rateLimitsResponse.startIndex,
            offsetBy: Self.rateLimitsResponse.count / 2
        )

        try await assertInvalidResponse(
            responses: [
                String(Self.rateLimitsResponse[..<midpoint]),
                String(Self.rateLimitsResponse[midpoint...]),
                Self.usageResponse
            ]
        )
    }

    func testRateLimitsRPCErrorRemainsFailure() async throws {
        let rateLimitsError = #"{"id":2,"error":{"code":-32603,"message":"Rate limits are temporarily unavailable"}}"#

        try await assertInvalidResponse(responses: [rateLimitsError])
    }

    func testInitializationRPCErrorRemainsFailure() async throws {
        let initializationError = #"{"id":1,"error":{"code":-32603,"message":"Initialization failed"}}"#

        try await assertInvalidResponse(responses: [initializationError])
    }

    func testMalformedUsageRPCErrorRemainsFailure() async throws {
        let malformedErrors = [
            #"{"id":3,"error":null}"#,
            #"{"id":3,"error":"bad envelope"}"#,
            #"{"id":3,"error":{"message":"Missing code"}}"#,
            #"{"id":3,"error":{"code":-32603}}"#
        ]

        for malformedError in malformedErrors {
            try await assertInvalidResponse(
                responses: [Self.rateLimitsResponse, malformedError]
            )
        }
    }

    func testMalformedUsageResponseRemainsFailure() throws {
        let usage = Data(#"""
        {"id":3,"result":{
          "dailyUsageBuckets":[
            {"startDate":"2001-01-01","tokens":"not-a-number"}
          ]
        }}
        """#.utf8)

        XCTAssertThrowsError(
            try CodexClient.decode(
                rateLimitsResponse: Data(Self.rateLimitsResponse.utf8),
                usageResponse: usage,
                fetchedAt: Self.fetchedAt
            )
        )
    }

    func testMalformedRateLimitsResponseRemainsFailure() throws {
        let rateLimits = Data(#"""
        {"id":2,"result":{
          "rateLimits":{"primary":{"usedPercent":"not-a-number","windowDurationMins":10080,"resetsAt":2000000}}
        }}
        """#.utf8)

        XCTAssertThrowsError(
            try CodexClient.decode(
                rateLimitsResponse: rateLimits,
                usageResponse: nil,
                fetchedAt: Self.fetchedAt
            )
        )
    }

    func testMissingResultEnvelopesRemainInvalid() throws {
        let inputs: [(rateLimits: Data, usage: Data?)] = [
            (Data(#"{"id":2}"#.utf8), nil),
            (
                Data(Self.rateLimitsResponse.utf8),
                Data(#"{"id":3}"#.utf8)
            )
        ]

        for input in inputs {
            do {
                _ = try CodexClient.decode(
                    rateLimitsResponse: input.rateLimits,
                    usageResponse: input.usage,
                    fetchedAt: Self.fetchedAt
                )
                XCTFail("Expected invalidResponse")
            } catch let error as CodexClientError {
                guard case .invalidResponse = error else {
                    return XCTFail("Expected invalidResponse, got \(error)")
                }
            }
        }
    }

    func testStructurallyValidRateLimitsWithoutAWindowReportsMissingMainLimit() throws {
        let rateLimits = Data(#"""
        {"id":2,"result":{"rateLimits":{"limitId":"codex"}}}
        """#.utf8)

        XCTAssertThrowsError(
            try CodexClient.decode(
                rateLimitsResponse: rateLimits,
                usageResponse: nil,
                fetchedAt: Self.fetchedAt
            )
        ) { error in
            guard let clientError = error as? CodexClientError,
                  case .mainLimitMissing = clientError else {
                return XCTFail("Expected mainLimitMissing, got \(error)")
            }
        }
    }

    func testFinalProtocolLineWithoutNewlineIsDecodedAtEOF() async throws {
        let result = try await readSnapshot(
            rawOutput: Self.rateLimitsResponse + "\n" + Self.usageResponse,
            fetchedAt: Self.fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory.map(\.tokens), [1_000])
    }

    private func fetchSnapshot(
        using server: AppServerFixture,
        executablePaths: [String] = ["/test/codex"],
        isExecutable: (String) -> Bool = { _ in true },
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async throws -> UsageSnapshot {
        try await CodexClient.fetch(
            executablePaths: executablePaths,
            isExecutable: isExecutable,
            retryDelayNanoseconds: 0,
            timeoutNanoseconds: timeoutNanoseconds,
            makeConnection: server.makeConnection(using:)
        )
    }

    private func readSnapshot(
        responses: [String],
        fetchedAt: Date
    ) async throws -> UsageSnapshot {
        try await readSnapshot(
            rawOutput: responses.joined(separator: "\n") + "\n",
            fetchedAt: fetchedAt
        )
    }

    private func readSnapshot(
        rawOutput: String,
        fetchedAt: Date
    ) async throws -> UsageSnapshot {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data(rawOutput.utf8)
        )
        try serverOutput.fileHandleForWriting.close()

        return try await CodexClient.readSnapshot(
            from: serverOutput.fileHandleForReading,
            writingTo: clientInput.fileHandleForWriting,
            fetchedAt: fetchedAt
        )
    }

    private func readBoundedLine(
        _ value: String,
        maximumBytes: Int
    ) async throws -> (line: Data?, stopCount: Int) {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        var stopCount = 0
        let connection = CodexAppServerConnection(
            input: clientInput.fileHandleForWriting,
            output: serverOutput.fileHandleForReading,
            maximumLineBytes: maximumBytes,
            start: {},
            stop: { stopCount += 1 }
        )
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data(value.utf8)
        )
        try serverOutput.fileHandleForWriting.close()

        return (try await connection.readLine(), stopCount)
    }

    private func assertInvalidResponse(
        responses: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            _ = try await readSnapshot(
                responses: responses,
                fetchedAt: Self.fetchedAt
            )
            XCTFail("Expected invalidResponse", file: file, line: line)
        } catch let error as CodexClientError {
            guard case .invalidResponse = error else {
                return XCTFail(
                    "Expected invalidResponse, got \(error)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private static let fetchedAt = Date(timeIntervalSince1970: 1_900_000)
    private static let usageErrorResponse = #"{"id":3,"error":{"code":-32603,"message":"Usage is temporarily unavailable"}}"#
    private static let usageResponse = #"{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2001-01-01","tokens":1000}]}}"#
    private static let rateLimitsResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}}},"rateLimitResetCredits":{"availableCount":3}}}"#
}

private final class AppServerFixture: @unchecked Sendable {
    enum Behavior {
        case success
        case initializationError
        case rateLimitsError
        case usageError
        case endOfFile
        case malformedOutput
        case stall
        case startFailure
    }

    private enum FixtureError: Error {
        case startFailed
    }

    private let lock = NSLock()
    private var behaviors: [Behavior]
    private var storedConnectionCount = 0
    private var storedStartCount = 0
    private var storedStopCount = 0
    private var storedExecutables: [String] = []
    private var storedRequestMethods: [String] = []

    init(behaviors: [Behavior]) {
        self.behaviors = behaviors
    }

    var connectionCount: Int {
        withLock { storedConnectionCount }
    }

    var startCount: Int {
        withLock { storedStartCount }
    }

    var stopCount: Int {
        withLock { storedStopCount }
    }

    var executables: [String] {
        withLock { storedExecutables }
    }

    var requestMethods: [String] {
        withLock { storedRequestMethods }
    }

    func makeConnection(using executable: String) -> CodexAppServerConnection {
        let behavior = withLock { () -> Behavior in
            storedConnectionCount += 1
            storedExecutables.append(executable)
            return behaviors.isEmpty ? .success : behaviors.removeFirst()
        }
        let clientInput = Pipe()
        let serverOutput = Pipe()

        return CodexAppServerConnection(
            input: clientInput.fileHandleForWriting,
            output: serverOutput.fileHandleForReading,
            start: { [self] in
                withLock { storedStartCount += 1 }
                switch behavior {
                case .startFailure:
                    throw FixtureError.startFailed
                case .endOfFile:
                    try serverOutput.fileHandleForWriting.close()
                case .malformedOutput:
                    try serverOutput.fileHandleForWriting.write(
                        contentsOf: Data("not-json\n".utf8)
                    )
                    try serverOutput.fileHandleForWriting.close()
                case .stall:
                    break
                case .success, .initializationError, .rateLimitsError, .usageError:
                    runServer(
                        behavior: behavior,
                        input: clientInput.fileHandleForReading,
                        output: serverOutput.fileHandleForWriting
                    )
                }
            },
            stop: { [self] in
                withLock { storedStopCount += 1 }
                try? clientInput.fileHandleForWriting.close()
                if case .stall = behavior {
                    // Model a wedged child that ignores termination and keeps
                    // stdout open. Client cancellation must still be bounded.
                } else {
                    try? serverOutput.fileHandleForWriting.close()
                }
            }
        )
    }

    private func runServer(
        behavior: Behavior,
        input: FileHandle,
        output: FileHandle
    ) {
        Task.detached { [self] in
            do {
                for try await line in input.bytes.lines {
                    guard let object = try? JSONSerialization.jsonObject(
                        with: Data(line.utf8)
                    ) as? [String: Any],
                          let method = object["method"] as? String else {
                        continue
                    }
                    withLock { storedRequestMethods.append(method) }
                    guard let response = response(
                        for: method,
                        behavior: behavior
                    ) else { continue }
                    try output.write(
                        contentsOf: Data((response + "\n").utf8)
                    )
                }
            } catch {
                // The client closes both pipes when an attempt finishes.
            }
        }
    }

    private func response(
        for method: String,
        behavior: Behavior
    ) -> String? {
        switch method {
        case "initialize":
            if case .initializationError = behavior {
                return #"{"id":1,"error":{"code":-32603,"message":"Initialization failed"}}"#
            }
            return #"{"id":1,"result":{}}"#
        case "account/rateLimits/read":
            if case .rateLimitsError = behavior {
                return #"{"id":2,"error":{"code":-32603,"message":"Rate limits failed"}}"#
            }
            return Self.rateLimitsResponse
        case "account/usage/read":
            if case .usageError = behavior {
                return #"{"id":3,"error":{"code":-32603,"message":"Usage failed"}}"#
            }
            return Self.usageResponse
        default:
            return nil
        }
    }

    private func withLock<Result>(_ operation: () -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }

    private static let rateLimitsResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}}}}"#
    private static let usageResponse = #"{"id":3,"result":{"dailyUsageBuckets":[{"startDate":"2001-01-01","tokens":1000}]}}"#
}

private actor RetryAttemptProbe {
    private var storedAttemptCount = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    var attemptCount: Int {
        storedAttemptCount
    }

    func fail() throws -> String {
        storedAttemptCount += 1
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
        throw CodexClientError.invalidResponse
    }

    func waitUntilAttempted() async {
        guard storedAttemptCount == 0 else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
