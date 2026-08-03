import XCTest
@testable import CodexLimits

final class ForecastEngineTests: XCTestCase {
    func testFastPaceNeedsSlowingDown() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(2 * 86_400)
        let window = UsageWindow(
            remainingPercent: 20,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        let samples = [
            UsageSample(observedAt: now.addingTimeInterval(-86_400), remainingPercent: 60, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 20, resetsAt: reset)
        ]

        let result = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        XCTAssertEqual(result.status, .slowDown)
        XCTAssertEqual(result.expectedRemainingAtReset, 0, accuracy: 0.01)
        XCTAssertEqual(result.recommendedPercentPerDay, 8.5, accuracy: 0.01)
    }

    func testIdleFreshWindowIsNotSlowedDownByPastBursts() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 3_000_000)
        let reset = now.addingTimeInterval(5 * day)
        let previousReset = now.addingTimeInterval(-2 * day)
        let window = UsageWindow(
            remainingPercent: 98,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        // Last window burned 50% in a five-hour burst; this window is nearly untouched.
        let samples = [
            UsageSample(observedAt: previousReset.addingTimeInterval(-6 * 3_600), remainingPercent: 90, resetsAt: previousReset),
            UsageSample(observedAt: previousReset.addingTimeInterval(-3_600), remainingPercent: 40, resetsAt: previousReset),
            UsageSample(observedAt: now.addingTimeInterval(-day), remainingPercent: 99, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 98, resetsAt: reset)
        ]

        let result = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        XCTAssertNotEqual(result.status, .slowDown)
    }

    func testHistoricalBurstRateIsSpreadOverAtLeastADay() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 3_000_000)
        let reset = now.addingTimeInterval(4 * day)
        let previousReset = now.addingTimeInterval(-day)
        let window = UsageWindow(
            remainingPercent: 60,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        // 12% drop over three hours must count as 12%/day, not 96%/day.
        let samples = [
            UsageSample(observedAt: previousReset.addingTimeInterval(-4 * 3_600), remainingPercent: 82, resetsAt: previousReset),
            UsageSample(observedAt: previousReset.addingTimeInterval(-3_600), remainingPercent: 70, resetsAt: previousReset)
        ]

        let result = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        XCTAssertEqual(result.historicalPercentPerDay, 12, accuracy: 0.01)
    }

    func testRecentPaceFollowsTheTrailingDayNotTheWholeWindow() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 3_000_000)
        let reset = now.addingTimeInterval(3 * day)
        let window = UsageWindow(
            remainingPercent: 50,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        // Heavy use three days ago, flat since yesterday.
        let samples = [
            UsageSample(observedAt: now.addingTimeInterval(-3.5 * day), remainingPercent: 100, resetsAt: reset),
            UsageSample(observedAt: now.addingTimeInterval(-3 * day), remainingPercent: 55, resetsAt: reset),
            UsageSample(observedAt: now.addingTimeInterval(-0.5 * day), remainingPercent: 50, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 50, resetsAt: reset)
        ]

        let result = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        // Whole-window average is ~14%/day; the trailing day is flat, so the
        // blended current pace must sit well below the window average.
        XCTAssertLessThan(result.currentPercentPerDay, 8)
    }

    func testEarlierDeadlineRaisesRecommendedPace() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(4 * 86_400)
        let deadline = now.addingTimeInterval(2 * 86_400)
        let window = UsageWindow(
            remainingPercent: 43,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        let samples = [
            UsageSample(observedAt: now.addingTimeInterval(-86_400), remainingPercent: 60, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 43, resetsAt: reset)
        ]

        let unconstrained = ForecastEngine.evaluate(
            window: window, samples: samples, tokenHistory: [],
            safetyBuffer: 3, now: now, previousStatus: nil
        )
        let constrained = ForecastEngine.evaluate(
            window: window, samples: samples, tokenHistory: [],
            safetyBuffer: 3, now: now, previousStatus: nil,
            deadline: deadline
        )

        XCTAssertEqual(unconstrained.recommendedPercentPerDay, 10, accuracy: 0.01)
        XCTAssertEqual(constrained.recommendedPercentPerDay, 20, accuracy: 0.01)
    }

    func testPaceDeadlineFollowsSelectedCreditOnlyWhileItQualifies() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let reset = now.addingTimeInterval(6 * 86_400)
        let window = UsageWindow(remainingPercent: 50, resetsAt: reset, durationMinutes: 7 * 24 * 60)
        let credits = [
            ResetCredit(id: "past", title: nil, expiresAt: now.addingTimeInterval(-3_600)),
            ResetCredit(id: "in-window", title: nil, expiresAt: now.addingTimeInterval(2 * 86_400)),
            ResetCredit(id: "after-reset", title: nil, expiresAt: now.addingTimeInterval(9 * 86_400)),
            ResetCredit(id: "open-ended", title: nil, expiresAt: nil)
        ]

        func deadline(_ id: String?) -> Date {
            ForecastEngine.paceDeadline(
                window: window, resetCredits: credits, now: now, selectedCreditID: id
            )
        }

        XCTAssertEqual(deadline("in-window"), now.addingTimeInterval(2 * 86_400))
        XCTAssertEqual(deadline(""), reset)
        XCTAssertEqual(deadline(nil), reset)
        XCTAssertEqual(deadline("past"), reset)
        XCTAssertEqual(deadline("after-reset"), reset)
        XCTAssertEqual(deadline("open-ended"), reset)
        XCTAssertEqual(deadline("no-such-credit"), reset)
    }

    func testQuietCurrentPaceLeavesRoomToUseMore() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 2_000_000)
        let reset = now.addingTimeInterval(2 * day)
        let earlierReset = now.addingTimeInterval(-7 * day)
        let window = UsageWindow(
            remainingPercent: 40,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        let samples = [
            UsageSample(observedAt: earlierReset.addingTimeInterval(-5 * day), remainingPercent: 100, resetsAt: earlierReset),
            UsageSample(observedAt: earlierReset, remainingPercent: 75, resetsAt: earlierReset),
            UsageSample(observedAt: now.addingTimeInterval(-day), remainingPercent: 42, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 40, resetsAt: reset)
        ]

        let result = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        XCTAssertEqual(result.status, .roomToUseMore)
        XCTAssertEqual(result.expectedRemainingAtReset, 30, accuracy: 0.01)
        XCTAssertEqual(result.historicalRemainingAtReset, 30, accuracy: 0.01)
    }

    func testTokenHistoryBootstrapsHistoricalPace() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 100 * day)
        let reset = now.addingTimeInterval(2 * day)
        let window = UsageWindow(
            remainingPercent: 90,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        let olderDays = (-33 ... -6).map {
            TokenDay(date: now.addingTimeInterval(Double($0) * day), tokens: 200)
        }
        let currentDays = (-5 ... -1).map {
            TokenDay(date: now.addingTimeInterval(Double($0) * day), tokens: 100)
        }

        let result = ForecastEngine.evaluate(
            window: window,
            samples: [],
            tokenHistory: olderDays + currentDays,
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        XCTAssertEqual(result.currentPercentPerDay, 2.5, accuracy: 0.01)
        XCTAssertEqual(result.historicalPercentPerDay, 4, accuracy: 0.01)
        XCTAssertEqual(result.expectedRemainingAtReset, 85, accuracy: 0.01)
    }

    func testSlowDownWaitsForOnePointOfRecovery() {
        let day: TimeInterval = 86_400
        let now = Date(timeIntervalSince1970: 200 * day)
        let reset = now.addingTimeInterval(3 * day)
        let previousReset = now.addingTimeInterval(-4 * day)
        // 40% left with 4 of 7 days elapsed: behind the target line (44.6%).
        let window = UsageWindow(
            remainingPercent: 40,
            resetsAt: reset,
            durationMinutes: 7 * 24 * 60
        )
        let samples = [
            UsageSample(observedAt: previousReset.addingTimeInterval(-3 * day), remainingPercent: 90, resetsAt: previousReset),
            UsageSample(observedAt: previousReset.addingTimeInterval(-day), remainingPercent: 69.6, resetsAt: previousReset),
            UsageSample(observedAt: now.addingTimeInterval(-0.9 * day), remainingPercent: 40, resetsAt: reset),
            UsageSample(observedAt: now, remainingPercent: 40, resetsAt: reset)
        ]

        let recovering = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: .slowDown
        )
        let fresh = ForecastEngine.evaluate(
            window: window,
            samples: samples,
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: nil
        )

        // The safety margin sits in the recovery band between 3 and 4 points.
        XCTAssertEqual(recovering.safetyRemainingAtReset, 3.28, accuracy: 0.01)
        XCTAssertEqual(recovering.status, .slowDown)
        XCTAssertNotEqual(fresh.status, .slowDown)
    }
}
