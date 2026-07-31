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
        let window = UsageWindow(
            remainingPercent: 49.210526,
            resetsAt: now.addingTimeInterval(3 * day),
            durationMinutes: 7 * 24 * 60
        )

        let result = ForecastEngine.evaluate(
            window: window,
            samples: [],
            tokenHistory: [],
            safetyBuffer: 3,
            now: now,
            previousStatus: .slowDown
        )

        XCTAssertEqual(result.safetyRemainingAtReset, 3.5, accuracy: 0.01)
        XCTAssertEqual(result.status, .slowDown)
    }
}
