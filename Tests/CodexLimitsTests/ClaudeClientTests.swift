import XCTest
@testable import CodexLimits

final class ClaudeClientTests: XCTestCase {
    private static let fetchedAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testMapsExactAccountWindowsAndKeepsModelWindowsSeparate() throws {
        var sonnet = ClaudeUsageFixture.limit("weekly_scoped", percent: 95)
        sonnet["scope"] = ["model": ["display_name": "Sonnet"]]
        let data = try ClaudeUsageFixture.output(limits: [
            ClaudeUsageFixture.limit("session", percent: 74.5, reset: "2027-01-15T09:00:00.123Z"),
            ClaudeUsageFixture.limit(percent: 40), sonnet
        ])
        let result = try ClaudeClient.decode(data, fetchedAt: Self.fetchedAt)
        XCTAssertEqual(result.mainLimit.limitId, "claude")
        XCTAssertEqual(result.mainLimit.name, "Claude Code")
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 25.5)
        XCTAssertEqual(result.mainLimit.window.durationMinutes, 300)
        let weekly = try XCTUnwrap(result.otherLimits.first { $0.limitId == "claude" })
        XCTAssertEqual(weekly.window.durationMinutes, 10_080)
        XCTAssertEqual(weekly.window.remainingPercent, 60)
        let model = try XCTUnwrap(result.otherLimits.first { $0.limitId == "claude-sonnet" })
        XCTAssertEqual(model.window.remainingPercent, 5)
        XCTAssertEqual(model.name, "Sonnet weekly")
        XCTAssertEqual(result.fetchedAt, Self.fetchedAt)
        XCTAssertTrue(result.tokenHistory.isEmpty)
        XCTAssertTrue(result.resetCredits.isEmpty)
        XCTAssertEqual(result.mainLimit.window.resetsAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.123, accuracy: 0.001)
        XCTAssertEqual(weekly.window.resetsAt.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.563632, accuracy: 0.001)
    }

    func testWeeklyCanBePrimaryWithoutLosingFiveHourWindow() throws {
        let result = try decode([
            ClaudeUsageFixture.limit("session", percent: 10), ClaudeUsageFixture.limit(percent: 80)
        ])
        XCTAssertEqual(result.mainLimit.window.durationMinutes, 10_080)
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 20)
        XCTAssertEqual(result.otherLimits.map(\.window.durationMinutes), [300])
    }

    func testInactiveSessionWithoutResetDoesNotInventAWindow() throws {
        let result = try decode([
            ClaudeUsageFixture.limit("session", percent: 0, reset: NSNull()), ClaudeUsageFixture.limit()
        ])
        XCTAssertEqual(result.mainLimit.window.durationMinutes, 10_080)
        XCTAssertTrue(result.otherLimits.isEmpty)
    }

    func testMissingUsageAndBadDatesReportUnavailableInsteadOfZero() {
        for limits in [[], [ClaudeUsageFixture.limit(reset: "invalid")], [ClaudeUsageFixture.limit(reset: NSNull())]] {
            XCTAssertThrowsError(try decode(limits)) {
                XCTAssertEqual($0 as? ClaudeClientError, .mainLimitMissing)
            }
        }
    }

    func testFailedFetchCannotReuseCLICachedOrHumanReadableUsage() throws {
        let data = try ClaudeUsageFixture.output(limits: nil)
        XCTAssertThrowsError(try ClaudeClient.decode(data, fetchedAt: Self.fetchedAt)) {
            XCTAssertEqual($0 as? ClaudeClientError, .usageUnavailable)
        }
    }

    func testRejectsIncompleteOrMalformedStream() throws {
        let data = try ClaudeUsageFixture.output()
        let incomplete = Data(data.prefix { $0 != 0x0A })
        for invalid in [Data(), Data("not json".utf8), incomplete] {
            XCTAssertThrowsError(try ClaudeClient.decode(invalid, fetchedAt: Self.fetchedAt)) {
                XCTAssertEqual($0 as? ClaudeClientError, .invalidResponse)
            }
        }
    }

    func testRejectsNonlocalCommandsAndModelTurns() throws {
        for data in [
            try ClaudeUsageFixture.output(command: "other"),
            try ClaudeUsageFixture.output(args: "inherited stdin"),
            try ClaudeUsageFixture.output(turns: 1),
            try ClaudeUsageFixture.output(cost: 0.001)
        ] {
            XCTAssertThrowsError(try ClaudeClient.decode(data, fetchedAt: Self.fetchedAt)) {
                XCTAssertEqual($0 as? ClaudeClientError, .cliUpdateRequired)
            }
        }
    }

    func testSignedOutCLIWithoutSubscriptionReportIsUnavailable() throws {
        let data = try ClaudeUsageFixture.output(includeReport: false)
        XCTAssertThrowsError(try ClaudeClient.decode(data, fetchedAt: Self.fetchedAt)) {
            XCTAssertEqual($0 as? ClaudeClientError, .usageUnavailable)
        }
    }

    func testErrorResultDoesNotAcceptEarlierReport() throws {
        let data = try ClaudeUsageFixture.output(isError: true)
        XCTAssertThrowsError(try ClaudeClient.decode(data, fetchedAt: Self.fetchedAt)) {
            XCTAssertEqual($0 as? ClaudeClientError, .commandFailed)
        }
    }

    func testClampsUtilizationToPercentageBounds() throws {
        let result = try decode([
            ClaudeUsageFixture.limit("session", percent: -5), ClaudeUsageFixture.limit(percent: 120)
        ])
        XCTAssertEqual(result.mainLimit.window.remainingPercent, 0)
        XCTAssertEqual(result.otherLimits.first?.window.remainingPercent, 100)
    }

    func testScopedLimitsHaveStableIDsAndIgnoreInactiveOrAccountScopes() throws {
        let scopes = [("sonnet", "Sonnet", true), ("fable", "Fable", true), ("opus", "Opus", false), ("all-models", "All models", true)]
        let limits = scopes.map { id, name, active in
            var limit = ClaudeUsageFixture.limit("weekly_scoped")
            limit["scope"] = ["model": ["id": id, "display_name": name]]
            limit["is_active"] = active
            return limit
        }
        let result = try decode([ClaudeUsageFixture.limit()] + limits)
        XCTAssertEqual(result.otherLimits.map(\.limitId), ["claude-fable", "claude-sonnet"])
    }

    func testSuccessfulSnapshotIsTimestampedWhenCommandCompletes() async throws {
        var currentDate = Self.fetchedAt
        let snapshot = try await ClaudeClient.fetch(now: { currentDate }, readAccount: { nil }) {
            currentDate = Self.fetchedAt.addingTimeInterval(20)
            return try ClaudeUsageFixture.output()
        }
        XCTAssertEqual(snapshot.fetchedAt, currentDate)
        XCTAssertNil(snapshot.accountEmail)
    }

    func testCancellationIsPreserved() async {
        do {
            _ = try await ClaudeClient.fetch(readAccount: { nil }) { throw CancellationError() }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch { XCTFail("Expected CancellationError") }
    }

    private func decode(_ limits: [[String: Any]]) throws -> UsageSnapshot {
        try ClaudeClient.decode(ClaudeUsageFixture.output(limits: limits), fetchedAt: Self.fetchedAt)
    }
}
