import XCTest
@testable import CodexLimits

final class UsageModelsTests: XCTestCase {
    func testSnapshotPersistedBeforeResetCreditsStillDecodes() throws {
        let legacy = Data(#"""
        {
          "mainLimit": {
            "limitId": "codex",
            "name": "Codex",
            "window": {"remainingPercent": 80, "resetsAt": 2000000, "durationMinutes": 10080}
          },
          "otherLimits": [],
          "tokenHistory": [],
          "emergencyResetCount": 2,
          "fetchedAt": 1900000
        }
        """#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let snapshot = try decoder.decode(UsageSnapshot.self, from: legacy)

        XCTAssertEqual(snapshot.mainLimit.window.remainingPercent, 80)
        XCTAssertEqual(snapshot.resetCredits, [])
        XCTAssertEqual(snapshot.fetchedAt, Date(timeIntervalSince1970: 1_900_000))
    }

    func testSnapshotRoundTripsResetCredits() throws {
        let snapshot = UsageSnapshot(
            mainLimit: LimitReading(
                limitId: "codex",
                name: "Codex",
                window: UsageWindow(
                    remainingPercent: 50,
                    resetsAt: Date(timeIntervalSince1970: 2_000_000),
                    durationMinutes: 10_080
                )
            ),
            otherLimits: [],
            tokenHistory: [],
            resetCredits: [
                ResetCredit(
                    id: "credit",
                    title: "Full reset",
                    expiresAt: Date(timeIntervalSince1970: 1_950_000)
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 1_900_000)
        )

        let decoded = try JSONDecoder().decode(
            UsageSnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )

        XCTAssertEqual(decoded, snapshot)
    }
}
