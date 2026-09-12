import XCTest
@testable import CodexLimits

final class HistoricalForecastTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var reset: Date { start.addingTimeInterval(7 * 86_400) }

    func testReconstructionDoesNotUseLaterReadingsFromAnyWindow() throws {
        let date = start.addingTimeInterval(2 * 86_400)
        let available = [sample(day: 1, remaining: 90), sample(day: 2, remaining: 80)]
        let baseline = try reconstruct(at: date, samples: available).get()
        let withFuture = try reconstruct(at: date, samples: available + [
            sample(day: 3, remaining: 5),
            UsageSample(observedAt: reset.addingTimeInterval(86_400), remainingPercent: 90,
                        resetsAt: reset.addingTimeInterval(7 * 86_400), durationMinutes: 10_080),
            UsageSample(observedAt: reset.addingTimeInterval(2 * 86_400), remainingPercent: 1,
                        resetsAt: reset.addingTimeInterval(7 * 86_400), durationMinutes: 10_080)
        ]).get()
        XCTAssertEqual(withFuture.forecast, baseline.forecast)
        XCTAssertEqual(withFuture.window, baseline.window)
        XCTAssertEqual(withFuture.samples, available)
    }

    func testGapUsesLastBalanceWithoutInterpolatingFromTheFuture() throws {
        let value = try reconstruct(at: start.addingTimeInterval(2 * 86_400), samples: [
            sample(day: 1, remaining: 85), sample(day: 3, remaining: 10)
        ]).get()
        XCTAssertEqual(value.window.remainingPercent, 85)
        XCTAssertEqual(value.lastReading.observedAt, start.addingTimeInterval(86_400))
        XCTAssertEqual(value.date, start.addingTimeInterval(2 * 86_400))
    }

    func testExactReadingIncludesThatReading() throws {
        let reading = sample(day: 2, remaining: 42)
        let value = try reconstruct(at: reading.observedAt, samples: [reading]).get()
        XCTAssertEqual(value.lastReading, reading)
        XCTAssertEqual(value.window.remainingPercent, 42)
    }

    func testNoReadingAndFutureDateReturnSpecificUnavailableReasons() {
        assertFailure(.noReading, reconstruct(at: start, samples: [sample(day: 1, remaining: 90)]))
        assertFailure(.futureDate, reconstruct(at: start.addingTimeInterval(11 * 86_400), samples: []))
    }

    func testExpiredReadingIsNotCarriedIntoAnUnobservedResetWindow() {
        assertFailure(.resetPassed, reconstruct(at: reset, samples: [sample(day: 6, remaining: 12)]))
    }

    func testEarlyResetUsesNewReadingAndOnlyNewWindowSamples() throws {
        let newReset = start.addingTimeInterval(9 * 86_400)
        let newReading = UsageSample(observedAt: start.addingTimeInterval(2 * 86_400), remainingPercent: 100,
                                     resetsAt: newReset, durationMinutes: 10_080)
        let value = try reconstruct(at: newReading.observedAt, samples: [sample(day: 1, remaining: 20), newReading]).get()
        XCTAssertEqual(value.window.resetsAt, newReset)
        XCTAssertEqual(value.samples, [newReading])
    }

    func testRecordedFiveHourDurationOverridesLegacyChoice() throws {
        let reading = UsageSample(observedAt: start.addingTimeInterval(3_600), remainingPercent: 75,
                                  resetsAt: start.addingTimeInterval(5 * 3_600), durationMinutes: 300)
        let value = try reconstruct(at: reading.observedAt, samples: [reading]).get()
        XCTAssertEqual(value.window.startsAt, start)
        XCTAssertEqual(value.window.durationMinutes, 300)
        XCTAssertFalse(value.assumedDuration)
    }

    func testLegacyDurationIsExplicitlyAssumed() throws {
        let value = try reconstruct(at: start.addingTimeInterval(86_400), samples: [sample(day: 1, remaining: 90, duration: nil)]).get()
        XCTAssertTrue(value.assumedDuration)
        XCTAssertEqual(value.window.durationMinutes, 10_080)
    }

    func testLegacyFiveHourChoiceRejectsReadingOutsideThatWindow() {
        let result = HistoricalForecast.reconstruct(at: start.addingTimeInterval(86_400),
            samples: [sample(day: 1, remaining: 90, duration: nil)],
            legacyDurationMinutes: 300, safetyBuffer: 3, now: reset)
        assertFailure(.invalidLegacyWindow, result)
    }

    func testEarlierMetadataInTheSameWindowSuppliesDuration() throws {
        let date = start.addingTimeInterval(2 * 86_400)
        let value = try reconstruct(at: date, samples: [
            sample(day: 1, remaining: 90), sample(day: 2, remaining: 80, duration: nil)
        ]).get()
        XCTAssertFalse(value.assumedDuration)
        XCTAssertEqual(value.window.remainingPercent, 80)
        XCTAssertEqual(value.window.durationMinutes, 10_080)
    }

    func testLaterMetadataDoesNotSelectLegacyWindowLength() throws {
        let value = try reconstruct(at: start.addingTimeInterval(2 * 86_400), samples: [
            sample(day: 1, remaining: 90, duration: nil), sample(day: 3, remaining: 80)
        ]).get()
        XCTAssertTrue(value.assumedDuration)
    }

    func testOtherLimitDurationsDoNotAffectHistoricalRate() throws {
        let date = start.addingTimeInterval(2 * 86_400)
        let available = [sample(day: 1, remaining: 90), sample(day: 2, remaining: 80)]
        let shortReset = start.addingTimeInterval(-86_400)
        let shortHistory = [
            UsageSample(observedAt: shortReset.addingTimeInterval(-4 * 3_600), remainingPercent: 100,
                        resetsAt: shortReset, durationMinutes: 300),
            UsageSample(observedAt: shortReset.addingTimeInterval(-3_600), remainingPercent: 1,
                        resetsAt: shortReset, durationMinutes: 300)
        ]
        let baseline = try reconstruct(at: date, samples: available).get()
        let withShort = try reconstruct(at: date, samples: shortHistory + available).get()
        XCTAssertEqual(withShort.forecast, baseline.forecast)
    }

    func testUnclassifiedPriorWindowsDoNotAffectHistoricalRate() throws {
        let date = start.addingTimeInterval(2 * 86_400)
        let available = [sample(day: 1, remaining: 90), sample(day: 2, remaining: 80)]
        let oldReset = start.addingTimeInterval(-86_400)
        let unclassified = [
            UsageSample(observedAt: oldReset.addingTimeInterval(-3_600), remainingPercent: 100, resetsAt: oldReset),
            UsageSample(observedAt: oldReset.addingTimeInterval(-60), remainingPercent: 1, resetsAt: oldReset)
        ]
        let baseline = try reconstruct(at: date, samples: available).get()
        let withUnclassified = try reconstruct(at: date, samples: unclassified + available).get()
        XCTAssertEqual(withUnclassified.forecast, baseline.forecast)
    }

    func testInvalidPercentagesAreIgnoredAndInvalidDurationsAreRejected() throws {
        let valid = sample(day: 1, remaining: 85)
        let value = try reconstruct(at: start.addingTimeInterval(2 * 86_400), samples: [
            valid, sample(day: 2, remaining: .nan), sample(day: 2, remaining: 120)
        ]).get()
        XCTAssertEqual(value.lastReading, valid)
        assertFailure(.invalidWindow, reconstruct(at: start.addingTimeInterval(86_400),
            samples: [sample(day: 1, remaining: 85, duration: 0)]))
    }

    func testKnownDurationWinsWhenLegacyAndNewRecordsHaveSameTimestamp() throws {
        let reading = sample(day: 1, remaining: 85)
        let old = sample(day: 1, remaining: 85, duration: nil)
        for records in [[reading, old], [old, reading]] {
            let value = try reconstruct(at: reading.observedAt, samples: records).get()
            XCTAssertFalse(value.assumedDuration)
            XCTAssertEqual(value.lastReading, reading)
        }
    }

    private func sample(day: Double, remaining: Double, duration: Int? = 10_080) -> UsageSample {
        UsageSample(observedAt: start.addingTimeInterval(day * 86_400), remainingPercent: remaining,
                    resetsAt: reset, durationMinutes: duration)
    }

    private func reconstruct(at date: Date, samples: [UsageSample]) -> Result<HistoricalForecast, HistoricalForecast.Unavailable> {
        HistoricalForecast.reconstruct(at: date, samples: samples,
            legacyDurationMinutes: 10_080, safetyBuffer: 3, now: start.addingTimeInterval(10 * 86_400))
    }

    private func assertFailure(_ expected: HistoricalForecast.Unavailable,
                               _ result: Result<HistoricalForecast, HistoricalForecast.Unavailable>,
                               file: StaticString = #filePath, line: UInt = #line) {
        if case let .failure(actual) = result { XCTAssertEqual(actual, expected, file: file, line: line) }
        else { XCTFail("Expected \(expected)", file: file, line: line) }
    }
}
