import XCTest
@testable import CodexLimits

final class StatusTextTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private func forecast(
        status: PaceStatus,
        expectedRemaining: Double = 20,
        safetyRate: Double = 10,
        safetyRemaining: Double = 0
    ) -> Forecast {
        Forecast(
            status: status,
            expectedRemainingAtReset: expectedRemaining,
            safetyRemainingAtReset: safetyRemaining,
            historicalRemainingAtReset: 0,
            recommendedPercentPerDay: 0,
            currentPercentPerDay: 0,
            historicalPercentPerDay: 0,
            safetyPercentPerDay: safetyRate
        )
    }

    func testTitles() {
        XCTAssertEqual(StatusText.title(.slowDown), "Consider slowing down")
        XCTAssertEqual(StatusText.title(.onTrack), "On track")
        XCTAssertEqual(StatusText.title(.roomToUseMore), "Allowance to spare")
    }

    func testSlowDownMessageCountsDaysToTheReset() {
        let reset = fetchedAt.addingTimeInterval(6 * day)

        let message = StatusText.message(
            forecast: forecast(status: .slowDown, safetyRate: 46),
            remainingPercent: 46,
            fetchedAt: fetchedAt,
            deadline: reset,
            windowReset: reset,
            safetyBuffer: 3
        )

        XCTAssertEqual(message, "With higher usage, your allowance could run out about 5 days before the scheduled reset.")
    }

    func testSlowDownMessageAgainstBankedExpiryNamesTheTarget() {
        let reset = fetchedAt.addingTimeInterval(6 * day)
        let expiry = fetchedAt.addingTimeInterval(day + 5 * 3_600)

        let message = StatusText.message(
            forecast: forecast(status: .slowDown, safetyRate: 46),
            remainingPercent: 46,
            fetchedAt: fetchedAt,
            deadline: expiry,
            windowReset: reset,
            safetyBuffer: 3
        )

        XCTAssertEqual(
            message,
            "With higher usage, your allowance could run out about 5 hours before the banked reset’s expiry."
        )
    }

    func testSlowDownMessageWithoutHeadroom() {
        let reset = fetchedAt.addingTimeInterval(day)

        let message = StatusText.message(
            forecast: forecast(status: .slowDown, safetyRate: 10),
            remainingPercent: 46,
            fetchedAt: fetchedAt,
            deadline: reset,
            windowReset: reset,
            safetyBuffer: 3
        )

        XCTAssertEqual(message, "With higher usage, you may have less than your 3% reserve left at the scheduled reset.")
    }

    func testRecoveryWarningNamesConfiguredBufferAndCustomTarget() {
        let deadline = fetchedAt.addingTimeInterval(day)
        let message = StatusText.message(
            forecast: forecast(status: .slowDown, safetyRate: 35.5, safetyRemaining: 10.5),
            remainingPercent: 46,
            fetchedAt: fetchedAt,
            deadline: deadline,
            windowReset: deadline.addingTimeInterval(day),
            safetyBuffer: 10,
            targetName: "your pacing target"
        )

        XCTAssertEqual(message, "With higher usage, you may finish close to your 10% reserve at your pacing target.")
    }

    func testOnTrackAndRoomMessages() {
        let reset = fetchedAt.addingTimeInterval(2 * day)

        XCTAssertEqual(
            StatusText.message(
                forecast: forecast(status: .onTrack, expectedRemaining: 12),
                remainingPercent: 40,
                fetchedAt: fetchedAt,
                deadline: reset,
                windowReset: reset,
                safetyBuffer: 3
            ),
            "Expected to have about 12% left at the scheduled reset."
        )
        XCTAssertEqual(
            StatusText.message(
                forecast: forecast(status: .roomToUseMore, expectedRemaining: 30),
                remainingPercent: 60,
                fetchedAt: fetchedAt,
                deadline: fetchedAt.addingTimeInterval(day),
                windowReset: reset,
                safetyBuffer: 3
            ),
            "Expected to have about 30% left at the banked reset’s expiry. Your reserve is 3%."
        )
    }

    func testPaceSwitchesToHourlyInsideTheFinalDay() {
        XCTAssertEqual(
            StatusText.pace(
                recommendedPercentPerDay: 24,
                deadline: fetchedAt.addingTimeInterval(12 * 3_600),
                now: fetchedAt
            ),
            "Up to 1.0% an hour"
        )
        XCTAssertEqual(
            StatusText.pace(
                recommendedPercentPerDay: 7.34,
                deadline: fetchedAt.addingTimeInterval(3 * day),
                now: fetchedAt
            ),
            "Up to 7.3% a day"
        )
    }

    func testDurationsPluralize() {
        XCTAssertEqual(StatusText.duration(30 * 60), "1 hour")
        XCTAssertEqual(StatusText.duration(5 * 3_600), "5 hours")
        XCTAssertEqual(StatusText.duration(day), "1 day")
        XCTAssertEqual(StatusText.duration(4.6 * day), "5 days")
    }

    func testUpdatedTextBuckets() {
        XCTAssertEqual(StatusText.updated(fetchedAt, now: fetchedAt.addingTimeInterval(30)), "Updated just now")
        XCTAssertEqual(StatusText.updated(fetchedAt, now: fetchedAt.addingTimeInterval(120)), "Updated 2 min ago")
        XCTAssertEqual(StatusText.updated(fetchedAt, now: fetchedAt.addingTimeInterval(3_600)), "Updated 1 hr ago")
        XCTAssertEqual(StatusText.updated(fetchedAt, now: fetchedAt.addingTimeInterval(2 * day)), "Updated 2 days ago")
    }
}
