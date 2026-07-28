import XCTest
@testable import CodexLimits

final class CodexClientTests: XCTestCase {
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
        XCTAssertEqual(result.emergencyResetCount, 3)
        XCTAssertEqual(result.fetchedAt, fetchedAt)
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

    private func readSnapshot(
        responses: [String],
        fetchedAt: Date
    ) async throws -> UsageSnapshot {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data((responses.joined(separator: "\n") + "\n").utf8)
        )
        try serverOutput.fileHandleForWriting.close()

        return try await CodexClient.readSnapshot(
            from: serverOutput.fileHandleForReading,
            writingTo: clientInput.fileHandleForWriting,
            fetchedAt: fetchedAt
        )
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
    private static let rateLimitsResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}}},"rateLimitResetCredits":{"availableCount":3}}}"#
}
