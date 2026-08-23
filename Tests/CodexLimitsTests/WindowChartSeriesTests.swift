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

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testTodayRateStartsAtTheLastSampleBeforeUsageBegan() throws {
        let hour: TimeInterval = 3_600
        // 12:00 UTC on a day well inside the window.
        let fetchedAt = Date(timeIntervalSince1970: 60 * day + 12 * hour)
        let startOfDay = Date(timeIntervalSince1970: 60 * day)
        let window = UsageWindow(
            remainingPercent: 68,
            resetsAt: fetchedAt.addingTimeInterval(3 * day),
            durationMinutes: 7 * 24 * 60
        )
        let reset = window.resetsAt
        let samples = [
            UsageSample(observedAt: startOfDay.addingTimeInterval(-hour), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: startOfDay.addingTimeInterval(30 * 60), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: startOfDay.addingTimeInterval(6 * hour), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: startOfDay.addingTimeInterval(8 * hour), remainingPercent: 74, resetsAt: reset)
        ]

        let rate = WindowChartSeries.todayRate(
            window: window,
            samples: samples,
            fetchedAt: fetchedAt,
            calendar: utcCalendar
        )

        // Usage began after the idle 06:00 sample: 12% over a quarter day.
        XCTAssertEqual(try XCTUnwrap(rate), 48, accuracy: 0.01)
    }

    func testTodayRateAnchorsToTheResetWhenTheWindowBeganToday() throws {
        let hour: TimeInterval = 3_600
        let fetchedAt = Date(timeIntervalSince1970: 60 * day + 10 * hour)
        let window = UsageWindow(
            remainingPercent: 90,
            resetsAt: fetchedAt.addingTimeInterval(7 * day - 6 * hour),
            durationMinutes: 7 * 24 * 60
        )
        let samples = [
            UsageSample(
                observedAt: fetchedAt.addingTimeInterval(-4 * hour),
                remainingPercent: 95,
                resetsAt: window.resetsAt
            )
        ]

        let rate = WindowChartSeries.todayRate(
            window: window,
            samples: samples,
            fetchedAt: fetchedAt,
            calendar: utcCalendar
        )

        // 10% since the 04:00 reset, a quarter day before now.
        XCTAssertEqual(try XCTUnwrap(rate), 40, accuracy: 0.01)
    }

    func testTodayRateIsNilWithoutUsageToday() {
        let hour: TimeInterval = 3_600
        let fetchedAt = Date(timeIntervalSince1970: 60 * day + 9 * hour)
        let window = UsageWindow(
            remainingPercent: 70,
            resetsAt: fetchedAt.addingTimeInterval(3 * day),
            durationMinutes: 7 * 24 * 60
        )
        let idle = [
            UsageSample(
                observedAt: fetchedAt.addingTimeInterval(-8 * hour),
                remainingPercent: 70,
                resetsAt: window.resetsAt
            ),
            UsageSample(
                observedAt: fetchedAt.addingTimeInterval(-4 * hour),
                remainingPercent: 70,
                resetsAt: window.resetsAt
            )
        ]

        XCTAssertNil(WindowChartSeries.todayRate(
            window: window,
            samples: idle,
            fetchedAt: fetchedAt,
            calendar: utcCalendar
        ))
        XCTAssertNil(WindowChartSeries.todayRate(
            window: window,
            samples: [],
            fetchedAt: fetchedAt,
            calendar: utcCalendar
        ))
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
