import XCTest
@testable import CodexLimits

final class StatusTextTests: XCTestCase {
    private let fetchedAt = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private func forecast(
        status: PaceStatus,
        expectedRemaining: Double = 20,
        safetyRate: Double = 10
    ) -> Forecast {
        Forecast(
            status: status,
            expectedRemainingAtReset: expectedRemaining,
            safetyRemainingAtReset: 0,
            historicalRemainingAtReset: 0,
            recommendedPercentPerDay: 0,
            currentPercentPerDay: 0,
            historicalPercentPerDay: 0,
            safetyPercentPerDay: safetyRate
        )
    }

    func testTitles() {
        XCTAssertEqual(StatusText.title(.slowDown), "Slow down")
        XCTAssertEqual(StatusText.title(.onTrack), "On track")
        XCTAssertEqual(StatusText.title(.roomToUseMore), "Room to use more")
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

        XCTAssertEqual(message, "At this pace, your limit may run out 5 days before the reset.")
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
            "At this pace, your limit may run out 5 hours before the banked reset expiry."
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

        XCTAssertEqual(message, "Your current pace is too close to the limit.")
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
            "You’re on track to have 12% left at the reset."
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
            "You can use about 27% more before the banked reset expiry."
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
