import XCTest
@testable import CodexLimits

final class ForecastConsistencyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)
    private let day: TimeInterval = 86_400

    func testWarningNamesConservativeForecastWhenExpectedPaceMeetsCustomTarget() throws {
        let window = UsageWindow(remainingPercent: 79, resetsAt: now.addingTimeInterval(6 * day), durationMinutes: 10_080)
        let deadline = now.addingTimeInterval(4 * day)
        let samples = [
            UsageSample(observedAt: window.startsAt.addingTimeInterval(-6 * day), remainingPercent: 100, resetsAt: window.startsAt),
            UsageSample(observedAt: window.startsAt.addingTimeInterval(-day), remainingPercent: 35, resetsAt: window.startsAt),
            UsageSample(observedAt: window.startsAt, remainingPercent: 100, resetsAt: window.resetsAt),
            UsageSample(observedAt: now, remainingPercent: 79, resetsAt: window.resetsAt)
        ]

        let forecast = ForecastEngine.evaluate(window: window, samples: samples, tokenHistory: [],
                                               safetyBuffer: 3, now: now, previousStatus: nil, deadline: deadline)
        let expected = WindowChartSeries.projection(window: window, fetchedAt: now, deadline: deadline,
                                                    rate: forecast.currentPercentPerDay,
                                                    remainingAtDeadline: forecast.expectedRemainingAtReset)
        let conservative = WindowChartSeries.projection(window: window, fetchedAt: now, deadline: deadline,
                                                        rate: forecast.safetyPercentPerDay,
                                                        remainingAtDeadline: forecast.safetyRemainingAtReset)
        let message = StatusText.message(forecast: forecast, remainingPercent: 79, fetchedAt: now,
                                         deadline: deadline, windowReset: window.resetsAt, safetyBuffer: 3,
                                         targetName: "selected target")

        XCTAssertEqual(forecast.status, .slowDown)
        XCTAssertEqual(expected.last, BurnPoint(date: deadline, remaining: 3))
        let exhaustion = try XCTUnwrap(conservative.last)
        XCTAssertEqual(exhaustion.remaining, 0)
        XCTAssertLessThan(exhaustion.date, deadline)
        XCTAssertEqual(message, "Conservative forecast: your limit may run out 21 hours before the selected target.")
    }

    func testStatusUsesTheDrawnTargetForEveryWindowLengthAndDeadline() {
        for durationMinutes in [300, 10_080] {
            let duration = Double(durationMinutes) * 60
            let start = now.addingTimeInterval(-duration / 5)
            let reset = start.addingTimeInterval(duration)
            for delay in [1, 60, duration / 3, reset.timeIntervalSince(now)] {
                let deadline = now.addingTimeInterval(delay)
                for reserve in [1.0, 3, 10] {
                    let target = PaceTarget(startsAt: start, deadline: deadline, reservePercent: reserve)
                    let balanceOnTarget = target.remainingPercent(at: now)
                    for difference in [-0.01, 0, 0.01] {
                        let window = UsageWindow(remainingPercent: balanceOnTarget + difference,
                                                 resetsAt: reset, durationMinutes: durationMinutes)
                        for previousStatus: PaceStatus? in [nil, .slowDown] {
                            let forecast = ForecastEngine.evaluate(window: window, samples: [], tokenHistory: [],
                                                                   safetyBuffer: reserve, now: now,
                                                                   previousStatus: previousStatus, deadline: deadline)
                            let context = "window=\(durationMinutes)m, target=+\(delay)s, buffer=\(reserve)%, balance difference=\(difference)"

                            if difference < 0 {
                                XCTAssertEqual(forecast.status, .slowDown, context)
                            } else {
                                XCTAssertNotEqual(forecast.status, .slowDown, context)
                            }
                        }
                    }
                }
            }
        }
    }

    func testConservativeEndpointMatchesWarningForScheduledBankedAndCustomTargets() throws {
        for durationMinutes in [300, 10_080] {
            let duration = Double(durationMinutes) * 60
            let window = UsageWindow(remainingPercent: 40, resetsAt: now.addingTimeInterval(duration * 0.8),
                                     durationMinutes: durationMinutes)
            let expiry = now.addingTimeInterval(duration / 2)
            let banked = ForecastEngine.paceDeadline(window: window,
                                                     resetCredits: [.init(id: "credit", title: nil, expiresAt: expiry)],
                                                     now: now, selectedCreditID: "credit")
            let custom = try [now.addingTimeInterval(1), now.addingTimeInterval(60), expiry,
                              window.resetsAt.addingTimeInterval(-1), window.resetsAt].map { date in
                try XCTUnwrap(BurndownTarget(date: date, window: window, now: now)).date
            }
            let targets: [(deadline: Date?, name: String?)] = [(nil, nil), (banked, nil)]
                + custom.map { ($0, "selected target") }

            for target in targets {
                let deadline = target.deadline ?? window.resetsAt
                for reserve in [1.0, 3, 10] {
                    let forecast = ForecastEngine.evaluate(window: window, samples: [], tokenHistory: [],
                                                           safetyBuffer: reserve, now: now, previousStatus: nil,
                                                           deadline: target.deadline)
                    let points = WindowChartSeries.projection(window: window, fetchedAt: now, deadline: deadline,
                                                              rate: forecast.safetyPercentPerDay,
                                                              remainingAtDeadline: forecast.safetyRemainingAtReset)
                    let endpoint = try XCTUnwrap(points.last)
                    let message = StatusText.message(forecast: forecast, remainingPercent: window.remainingPercent,
                                                     fetchedAt: now, deadline: deadline, windowReset: window.resetsAt,
                                                     safetyBuffer: reserve, targetName: target.name)
                    let targetName = target.name ?? (target.deadline == nil ? "reset" : "banked reset expiry")

                    XCTAssertEqual(points.first, BurnPoint(date: now, remaining: 40))
                    XCTAssertGreaterThan(endpoint.date, now)
                    XCTAssertLessThanOrEqual(endpoint.date, deadline)
                    XCTAssertTrue(message.contains(targetName))
                    if forecast.status == .slowDown, endpoint.date < deadline {
                        XCTAssertEqual(endpoint.remaining, 0)
                        let early = StatusText.duration(deadline.timeIntervalSince(endpoint.date))
                        XCTAssertEqual(message, "Conservative forecast: your limit may run out \(early) before the \(targetName).")
                    } else if forecast.status == .slowDown {
                        XCTAssertEqual(endpoint.date, deadline)
                        XCTAssertTrue(message.contains("conservative forecast"))
                        XCTAssertTrue(message.contains("\(Int(reserve))% buffer"))
                    } else {
                        XCTAssertEqual(endpoint.date, deadline)
                        XCTAssertGreaterThanOrEqual(endpoint.remaining, reserve)
                    }
                }
            }
        }
    }
}
