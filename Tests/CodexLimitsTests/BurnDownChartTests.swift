import SwiftUI
import XCTest
@testable import CodexLimits

final class BurnDownChartTests: XCTestCase {
    @MainActor
    func testTodayProjectionUsesSelectedDeadlineAndStopsAtExhaustion() throws {
        let day: TimeInterval = 86_400
        let now = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_000_000))
            .addingTimeInterval(day / 2)

        for durationMinutes in [300, 10_080] {
            let duration = Double(durationMinutes) * 60
            let window = UsageWindow(remainingPercent: 70, resetsAt: now.addingTimeInterval(duration * 0.8),
                                     durationMinutes: durationMinutes)
            let samples = [UsageSample(observedAt: now.addingTimeInterval(-min(duration / 10, day / 4)),
                                       remainingPercent: 71, resetsAt: window.resetsAt)]
            let rate = try XCTUnwrap(WindowChartSeries.todayRate(window: window, samples: samples, fetchedAt: now))
            let credit = ResetCredit(id: "credit", title: nil, expiresAt: now.addingTimeInterval(duration / 4))
            let bankedDeadline = ForecastEngine.paceDeadline(window: window, resetCredits: [credit],
                                                            now: now, selectedCreditID: credit.id)
            let deadlines = [now.addingTimeInterval(60), now.addingTimeInterval(duration / 3),
                             bankedDeadline, window.resetsAt]

            for deadline in deadlines {
                let forecast = ForecastEngine.evaluate(window: window, samples: samples, tokenHistory: [],
                                                       safetyBuffer: 3, now: now, previousStatus: nil, deadline: deadline)
                let chart = BurnDownChart(window: window, samples: samples, tokenHistory: [], fetchedAt: now,
                                          forecast: forecast, safetyBuffer: 3, resetCredits: [credit],
                                          paceDeadline: deadline, paceTargetCreditID: .constant(""))
                let endpoint = try XCTUnwrap(chart.todayProjection.last)
                let exhaustion = now.addingTimeInterval(window.remainingPercent / rate * day)

                XCTAssertEqual(chart.todayProjection.first, BurnPoint(date: now, remaining: 70))
                XCTAssertEqual(endpoint.date, min(deadline, exhaustion))
                XCTAssertEqual(endpoint.remaining,
                               max(70 - rate * deadline.timeIntervalSince(now) / day, 0), accuracy: 0.0001)
            }
        }
    }
}
