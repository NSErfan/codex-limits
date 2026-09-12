import XCTest
@testable import CodexLimits

final class BurndownTargetTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private var window: UsageWindow {
        UsageWindow(remainingPercent: 60, resetsAt: now.addingTimeInterval(3 * 86_400), durationMinutes: 10_080)
    }

    func testOnlyFutureDatesInTheCurrentWindowAreAccepted() {
        XCTAssertNil(BurndownTarget(date: now.addingTimeInterval(-1), window: window, now: now))
        XCTAssertNil(BurndownTarget(date: now, window: window, now: now))
        XCTAssertNotNil(BurndownTarget(date: now.addingTimeInterval(1), window: window, now: now))
        XCTAssertNotNil(BurndownTarget(date: window.resetsAt, window: window, now: now))
        XCTAssertNil(BurndownTarget(date: window.resetsAt.addingTimeInterval(1), window: window, now: now))
    }

    func testTargetExpiresAndDoesNotCarryAcrossAnEarlyReset() throws {
        let date = now.addingTimeInterval(86_400)
        let target = try XCTUnwrap(BurndownTarget(date: date, window: window, now: now))
        XCTAssertTrue(target.isValid(in: window, now: date.addingTimeInterval(-1)))
        XCTAssertFalse(target.isValid(in: window, now: date))
        let resetWindow = UsageWindow(remainingPercent: 100, resetsAt: now.addingTimeInterval(7 * 86_400), durationMinutes: 10_080)
        XCTAssertFalse(target.isValid(in: resetWindow, now: now))
    }

    func testFutureTargetChangesTheForecastHorizonWithoutChangingObservedUsage() throws {
        let target = try XCTUnwrap(BurndownTarget(date: now.addingTimeInterval(86_400), window: window, now: now))
        let samples = [
            UsageSample(observedAt: now.addingTimeInterval(-86_400), remainingPercent: 70, resetsAt: window.resetsAt),
            UsageSample(observedAt: now, remainingPercent: 60, resetsAt: window.resetsAt)
        ]
        let scheduled = ForecastEngine.evaluate(window: window, samples: samples, tokenHistory: [],
                                                safetyBuffer: 3, now: now, previousStatus: nil)
        let custom = ForecastEngine.evaluate(window: window, samples: samples, tokenHistory: [],
                                             safetyBuffer: 3, now: now, previousStatus: nil, deadline: target.date)
        XCTAssertEqual(custom.currentPercentPerDay, scheduled.currentPercentPerDay)
        XCTAssertEqual(custom.recommendedPercentPerDay, 57, accuracy: 0.001)
        XCTAssertEqual(scheduled.recommendedPercentPerDay, 19, accuracy: 0.001)
        XCTAssertGreaterThan(custom.expectedRemainingAtReset, scheduled.expectedRemainingAtReset)
        let projection = WindowChartSeries.projection(window: window, fetchedAt: now, deadline: target.date,
                                                       rate: custom.currentPercentPerDay,
                                                       remainingAtDeadline: custom.expectedRemainingAtReset)
        XCTAssertEqual(projection.first, BurnPoint(date: now, remaining: 60))
        XCTAssertEqual(projection.last?.date, target.date)
        let message = StatusText.message(forecast: custom, remainingPercent: 60, fetchedAt: now,
                                         deadline: target.date, windowReset: window.resetsAt,
                                         safetyBuffer: 3, targetName: "selected target")
        XCTAssertTrue(message.contains("selected target"))
        XCTAssertFalse(message.contains("banked reset"))
    }
}
