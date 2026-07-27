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
        let serverOutput = Pipe()
        let clientInput = Pipe()
        let rateLimits = Self.rateLimitsResponse
        let usageError = #"{"id":3,"error":{"code":-32603,"message":"Usage is temporarily unavailable"}}"#
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data((usageError + "\n" + rateLimits + "\n").utf8)
        )
        try serverOutput.fileHandleForWriting.close()
        let fetchedAt = Date(timeIntervalSince1970: 1_900_000)

        let result = try await CodexClient.readSnapshot(
            from: serverOutput.fileHandleForReading,
            writingTo: clientInput.fileHandleForWriting,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(result.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(result.tokenHistory, [])
        XCTAssertEqual(result.fetchedAt, fetchedAt)
    }

    func testRateLimitsRPCErrorRemainsFailure() async throws {
        let serverOutput = Pipe()
        let clientInput = Pipe()
        let rateLimitsError = #"{"id":2,"error":{"code":-32603,"message":"Rate limits are temporarily unavailable"}}"#
        try serverOutput.fileHandleForWriting.write(
            contentsOf: Data((rateLimitsError + "\n").utf8)
        )
        try serverOutput.fileHandleForWriting.close()

        do {
            _ = try await CodexClient.readSnapshot(
                from: serverOutput.fileHandleForReading,
                writingTo: clientInput.fileHandleForWriting,
                fetchedAt: Date(timeIntervalSince1970: 1_900_000)
            )
            XCTFail("Expected the rate-limits error to remain fatal")
        } catch let error as CodexClientError {
            guard case .invalidResponse = error else {
                return XCTFail("Expected invalidResponse, got \(error)")
            }
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
                fetchedAt: Date(timeIntervalSince1970: 1_900_000)
            )
        )
    }

    private static let rateLimitsResponse = #"{"id":2,"result":{"rateLimits":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":20,"windowDurationMins":10080,"resetsAt":2000000}}},"rateLimitResetCredits":{"availableCount":3}}}"#
}
