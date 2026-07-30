import XCTest
@testable import CodexLimits

final class WindowChartSeriesTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    private var window: UsageWindow {
        UsageWindow(
            remainingPercent: 70,
            resetsAt: start.addingTimeInterval(7 * day),
            durationMinutes: 7 * 24 * 60
        )
    }

    func testObservedBootstrapsFromTokenHistoryUntilFirstSample() {
        let reset = window.resetsAt
        let fetchedAt = start.addingTimeInterval(3 * day)
        let samples = [
            UsageSample(observedAt: start.addingTimeInterval(2 * day), remainingPercent: 80, resetsAt: reset)
        ]
        let tokenHistory = [
            TokenDay(date: start, tokens: 100),
            TokenDay(date: start.addingTimeInterval(day), tokens: 300)
        ]

        let observed = WindowChartSeries.observed(
            window: window,
            samples: samples,
            tokenHistory: tokenHistory,
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(observed.map(\.date), [
            start,
            start.addingTimeInterval(day),
            start.addingTimeInterval(2 * day),
            fetchedAt
        ])
        XCTAssertEqual(observed.map(\.remaining), [100, 95, 80, 70])
    }

    func testObservedWithoutTokensIsSyntheticStartSamplesAndCurrent() {
        let reset = window.resetsAt
        let fetchedAt = start.addingTimeInterval(day)
        let samples = [
            UsageSample(observedAt: start.addingTimeInterval(3_600), remainingPercent: 90, resetsAt: reset)
        ]

        let observed = WindowChartSeries.observed(
            window: window,
            samples: samples,
            tokenHistory: [],
            fetchedAt: fetchedAt
        )

        XCTAssertEqual(observed.map(\.remaining), [100, 90, 70])
    }

    func testProjectionReachesZeroBeforeDeadline() {
        let fetchedAt = start.addingTimeInterval(day)

        let points = WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: window.resetsAt,
            rate: 35,
            remainingAtDeadline: 10
        )

        XCTAssertEqual(points.first, BurnPoint(date: fetchedAt, remaining: 70))
        XCTAssertEqual(points.last, BurnPoint(date: fetchedAt.addingTimeInterval(2 * day), remaining: 0))
    }

    func testSlowProjectionEndsAtDeadlineWithForecastRemaining() {
        let fetchedAt = start.addingTimeInterval(day)
        let deadline = start.addingTimeInterval(2 * day)

        let points = WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: deadline,
            rate: 5,
            remainingAtDeadline: 65
        )

        XCTAssertEqual(points.last, BurnPoint(date: deadline, remaining: 65))
    }

    func testZeroRateProjectionStaysFlat() {
        let fetchedAt = start.addingTimeInterval(day)

        let points = WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: window.resetsAt,
            rate: 0,
            remainingAtDeadline: 70
        )

        XCTAssertEqual(points.map(\.remaining), [70, 70])
        XCTAssertEqual(points.last?.date, window.resetsAt)
    }

    func testVisibleCreditsRequireExpiryInsideTheWindow() {
        let credits = [
            ResetCredit(id: "inside", title: nil, expiresAt: start.addingTimeInterval(2 * day)),
            ResetCredit(id: "before", title: nil, expiresAt: start.addingTimeInterval(-day)),
            ResetCredit(id: "after", title: nil, expiresAt: start.addingTimeInterval(9 * day)),
            ResetCredit(id: "open-ended", title: nil, expiresAt: nil)
        ]

        let visible = WindowChartSeries.visibleCredits(credits, window: window)

        XCTAssertEqual(visible.map(\.id), ["inside"])
    }
}
