import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

final class CopilotClientTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_791_000_000)

    func testBusinessSeatTracksPremiumRequestsAcrossTheCalendarMonth() throws {
        let snapshot = try decode(Self.businessSeat)

        XCTAssertEqual(snapshot.mainLimit.limitId, "copilot")
        XCTAssertEqual(snapshot.mainLimit.name, "Premium requests")
        XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 93.8)
        XCTAssertEqual(snapshot.mainLimit.window.resetsAt, try date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(snapshot.mainLimit.window.startsAt, try date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(snapshot.mainLimit.window.durationMinutes, 31 * 1_440)
        XCTAssertTrue(snapshot.otherLimits.isEmpty, "Unlimited chat and completions have no balance to show")
        XCTAssertEqual(snapshot.accountName, "octocat")
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        XCTAssertEqual(snapshot.limit(for: .monthly, provider: .copilot), snapshot.mainLimit)
        XCTAssertNil(snapshot.limit(for: .weekly, provider: .copilot))
    }

    func testPlanWithoutPremiumRequestsIsBoundedByItsTightestQuota() throws {
        let snapshot = try decode("""
        {"quota_reset_date": "2026-11-01", "quota_snapshots": {
          "premium_interactions": {"entitlement": 0, "remaining": 0, "percent_remaining": 100, "unlimited": false},
          "chat": {"entitlement": 50, "remaining": 10, "percent_remaining": 20, "unlimited": false},
          "completions": {"entitlement": 2000, "remaining": 1500, "percent_remaining": 75, "unlimited": false}
        }}
        """)

        XCTAssertEqual(snapshot.mainLimit.limitId, "copilot")
        XCTAssertEqual(snapshot.mainLimit.name, "Chat messages")
        XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 20)
        XCTAssertEqual(snapshot.otherLimits.map(\.limitId), ["copilot-completions"])
        XCTAssertEqual(snapshot.otherLimits.map(\.name), ["Code completions"])
        XCTAssertEqual(snapshot.otherLimits.map(\.window.remainingPercent), [75])
        XCTAssertEqual(UsageDashboardPreferences.otherLimits(in: snapshot, provider: .copilot), snapshot.otherLimits)
    }

    func testMeteredQuotasBesidePremiumRequestsAreShownAsOtherLimits() throws {
        let snapshot = try decode("""
        {"quota_reset_date_utc": "2026-11-01T00:00:00.000Z", "quota_snapshots": {
          "premium_interactions": {"entitlement": 300, "remaining": 270, "percent_remaining": 90, "unlimited": false},
          "chat": {"entitlement": 50, "remaining": 5, "percent_remaining": 10, "unlimited": false}
        }}
        """)

        XCTAssertEqual(snapshot.mainLimit.name, "Premium requests")
        XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 90)
        XCTAssertEqual(snapshot.otherLimits.map(\.limitId), ["copilot-chat"])
        XCTAssertEqual(snapshot.otherLimits.map(\.window.remainingPercent), [10])
    }

    func testMonthlyCountsWithoutQuotaSnapshotsAreConvertedToPercentages() throws {
        let snapshot = try decode("""
        {"limited_user_reset_date": "2026-11-15",
         "monthly_quotas": {"chat": 50, "completions": 2000},
         "limited_user_quotas": {"chat": 40, "completions": 500}}
        """)

        XCTAssertEqual(snapshot.mainLimit.name, "Code completions")
        XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 25)
        XCTAssertEqual(snapshot.mainLimit.window.startsAt, try date("2026-10-15T00:00:00Z"))
        XCTAssertEqual(snapshot.otherLimits.map(\.window.remainingPercent), [80])
    }

    func testRemainingCountIsUsedWhenPercentageIsMissingAndOverageClampsToZero() throws {
        let derived = try decode("""
        {"quota_reset_date": "2026-11-01", "quota_snapshots": {
          "premium_interactions": {"entitlement": 300, "remaining": 75, "unlimited": false}}}
        """)
        XCTAssertEqual(derived.mainLimit.window.remainingPercent, 25)

        let overage = try decode("""
        {"quota_reset_date": "2026-11-01", "quota_snapshots": {
          "premium_interactions": {"entitlement": 300, "remaining": -30, "percent_remaining": -10, "unlimited": false}}}
        """)
        XCTAssertEqual(overage.mainLimit.window.remainingPercent, 0)
    }

    func testShortMonthsStillClassifyAsMonthlyPeriods() throws {
        let snapshot = try decode("""
        {"quota_reset_date": "2027-03-01", "quota_snapshots": {
          "premium_interactions": {"entitlement": 300, "remaining": 150, "percent_remaining": 50, "unlimited": false}}}
        """)

        XCTAssertEqual(snapshot.mainLimit.window.durationMinutes, 28 * 1_440)
        XCTAssertEqual(snapshot.mainLimit.window.startsAt, try date("2027-02-01T00:00:00Z"))
        XCTAssertNotNil(snapshot.limit(for: .monthly, provider: .copilot))
    }

    func testUnlimitedAccountHasNoAllowanceToTrack() {
        XCTAssertThrowsError(try decode("""
        {"quota_reset_date": "2026-11-01", "quota_snapshots": {
          "premium_interactions": {"entitlement": 0, "remaining": 0, "percent_remaining": 100, "unlimited": true},
          "chat": {"entitlement": 0, "remaining": 0, "percent_remaining": 100, "unlimited": true}}}
        """)) { error in
            XCTAssertEqual(error as? CopilotClientError, .allowanceNotMetered)
            XCTAssertFalse((error as? CopilotClientError)?.requiresLogin ?? true)
        }
    }

    func testMissingResetDateIsReported() {
        XCTAssertThrowsError(try decode("""
        {"quota_snapshots": {"premium_interactions": {"entitlement": 300, "remaining": 30, "percent_remaining": 10}}}
        """)) { error in
            XCTAssertEqual(error as? CopilotClientError, .resetDateMissing)
        }
    }

    func testHTTPStatusesMapToActionableErrors() {
        let cases: [(Int, CopilotClientError, requiresLogin: Bool, retries: Bool)] = [
            (401, .unauthorized, true, false),
            (403, .forbidden, false, false),
            (404, .copilotUnavailable, false, false),
            (429, .rateLimited, false, false),
            (502, .httpStatus(502), false, true),
            (418, .httpStatus(418), false, false)
        ]
        for (status, expected, requiresLogin, retries) in cases {
            XCTAssertThrowsError(try CopilotClient.decode(.init(statusCode: status, body: Data("{}".utf8)), fetchedAt: fetchedAt)) {
                let error = $0 as? CopilotClientError
                XCTAssertEqual(error, expected, "HTTP \(status)")
                XCTAssertEqual(error?.requiresLogin, requiresLogin, "HTTP \(status)")
                XCTAssertEqual(error?.shouldRetryAutomatically, retries, "HTTP \(status)")
            }
        }
        XCTAssertThrowsError(try decode("not json")) {
            XCTAssertEqual($0 as? CopilotClientError, .invalidResponse)
        }
    }

    func testFetchStampsTheReadingWithTheCompletionTime() async throws {
        let body = Data(Self.businessSeat.utf8)
        let snapshot = try await CopilotClient.fetch(now: { self.fetchedAt }) {
            .init(statusCode: 200, body: body)
        }
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
    }

    private func decode(_ json: String) throws -> UsageSnapshot {
        try CopilotClient.decode(.init(statusCode: 200, body: Data(json.utf8)), fetchedAt: fetchedAt)
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }

    /// Shape of a real `copilot_internal/user` response for a token-billed Business seat, with identifiers replaced.
    private static let businessSeat = """
    {
      "login": "octocat",
      "access_type_sku": "copilot_for_business_seat_quota",
      "copilot_plan": "business",
      "quota_reset_date": "2026-11-01",
      "quota_reset_date_utc": "2026-11-01T00:00:00.000Z",
      "token_based_billing": true,
      "quota_snapshots": {
        "chat": {
          "overage_count": 0, "overage_permitted": false, "percent_remaining": 100.0, "quota_id": "chat",
          "quota_remaining": 0.0, "unlimited": true, "timestamp_utc": "2026-10-08T11:18:34.042Z",
          "has_quota": true, "quota_reset_at": 0, "token_based_billing": true, "credits_used": 0,
          "overage_entitlement": 0, "remaining": 0, "entitlement": 0
        },
        "completions": {
          "overage_count": 0, "overage_permitted": false, "percent_remaining": 100.0, "quota_id": "completions",
          "quota_remaining": 0.0, "unlimited": true, "timestamp_utc": "2026-10-08T11:18:34.042Z",
          "has_quota": true, "quota_reset_at": 0, "token_based_billing": true, "credits_used": 0,
          "overage_entitlement": 0, "remaining": 0, "entitlement": 0
        },
        "premium_interactions": {
          "overage_count": 0, "overage_permitted": true, "percent_remaining": 93.8, "quota_id": "premium_interactions",
          "quota_remaining": 65714.9, "unlimited": false, "timestamp_utc": "2026-10-08T11:18:34.042Z",
          "has_quota": true, "quota_reset_at": 0, "token_based_billing": true, "credits_used": 4285,
          "overage_entitlement": 0, "remaining": 65714, "entitlement": 70000
        }
      }
    }
    """
}
