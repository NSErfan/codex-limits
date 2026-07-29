import XCTest
@testable import CodexLimits

final class HistorySeriesBuilderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testContinuousSamplesFormOneRunWithoutConnectors() {
        let reset = start.addingTimeInterval(7 * 86_400)
        let samples = (0 ..< 4).map {
            UsageSample(
                observedAt: start.addingTimeInterval(Double($0) * 600),
                remainingPercent: 100 - Double($0),
                resetsAt: reset
            )
        }

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.runs.count, 1)
        XCTAssertTrue(series.connectors.isEmpty)
    }

    func testGapSplitsRunsAndCreatesConnectorBetweenSurroundingPoints() {
        let reset = start.addingTimeInterval(7 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 90, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 88, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(10 * 3_600), remainingPercent: 70, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(10 * 3_600 + 600), remainingPercent: 69, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.runs.count, 2)
        XCTAssertEqual(series.connectors.count, 1)
        XCTAssertEqual(series.connectors[0].start.remainingPercent, 88)
        XCTAssertEqual(series.connectors[0].end.remainingPercent, 70)
    }

    func testResetJumpWithoutGapStaysInOneRun() {
        let firstReset = start.addingTimeInterval(3_600)
        let secondReset = start.addingTimeInterval(7 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 5, resetsAt: firstReset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 4, resetsAt: firstReset),
            UsageSample(observedAt: start.addingTimeInterval(1_200), remainingPercent: 100, resetsAt: secondReset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... secondReset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.runs.count, 1)
        XCTAssertEqual(series.runs[0].points.map(\.remainingPercent), [5, 4, 100])
        XCTAssertTrue(series.connectors.isEmpty)
    }

    func testExcludesSamplesOutsideRange() {
        let reset = start.addingTimeInterval(10 * 86_400)
        let samples = [
            UsageSample(observedAt: start.addingTimeInterval(-3_600), remainingPercent: 90, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(3_600), remainingPercent: 85, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(8 * 86_400), remainingPercent: 60, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... start.addingTimeInterval(7 * 86_400),
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.runs.count, 1)
        XCTAssertEqual(series.runs[0].points.map(\.remainingPercent), [85])
    }

    func testKeepsMinimumPointPerBucketAndRunEdges() {
        let reset = start.addingTimeInterval(7 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 100, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 98, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(1_200), remainingPercent: 96, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(2_000), remainingPercent: 94, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(2_400), remainingPercent: 92, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(3_000), remainingPercent: 90, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.runs.count, 1)
        XCTAssertEqual(series.runs[0].points.map(\.remainingPercent), [100, 96, 92, 90])
        XCTAssertEqual(series.runs[0].points.first?.date, start)
        XCTAssertEqual(series.runs[0].points.last?.date, start.addingTimeInterval(3_000))
    }

    func testJumpAtScheduledResetIsAnnotatedAtTheScheduledTime() {
        let firstReset = start.addingTimeInterval(1_000)
        let secondReset = start.addingTimeInterval(7 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 5, resetsAt: firstReset),
            UsageSample(observedAt: start.addingTimeInterval(1_800), remainingPercent: 100, resetsAt: secondReset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... secondReset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.resets, [firstReset])
    }

    func testJumpAcrossGapWithoutScheduledResetUsesObservationTime() {
        let reset = start.addingTimeInterval(30 * 86_400)
        let observedJump = start.addingTimeInterval(3 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 40, resetsAt: start.addingTimeInterval(-60)),
            UsageSample(observedAt: observedJump, remainingPercent: 98, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.resets, [observedJump])
    }

    func testSmallUpwardJitterIsNotAReset() {
        let reset = start.addingTimeInterval(7 * 86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 82, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertTrue(series.resets.isEmpty)
    }

    func testEmptyInputProducesEmptySeries() {
        let series = HistorySeriesBuilder.series(
            from: [],
            in: start ... start.addingTimeInterval(86_400),
            bucketDuration: 1_800
        )

        XCTAssertTrue(series.isEmpty)
        XCTAssertTrue(series.connectors.isEmpty)
    }
}
