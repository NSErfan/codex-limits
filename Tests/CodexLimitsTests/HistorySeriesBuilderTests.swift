import XCTest
@testable import CodexLimits

final class HistorySeriesBuilderTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    func testGroupsSamplesIntoOneSeriesPerWindowSortedByReset() {
        let firstReset = start.addingTimeInterval(2 * 86_400)
        let secondReset = start.addingTimeInterval(9 * 86_400)
        let samples = [
            UsageSample(observedAt: start.addingTimeInterval(3 * 86_400), remainingPercent: 95, resetsAt: secondReset),
            UsageSample(observedAt: start.addingTimeInterval(3_600), remainingPercent: 80, resetsAt: firstReset),
            UsageSample(observedAt: start.addingTimeInterval(7_200), remainingPercent: 70, resetsAt: firstReset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... start.addingTimeInterval(7 * 86_400),
            bucketDuration: 1_800
        )

        XCTAssertEqual(series.map(\.resetsAt), [firstReset, secondReset])
        XCTAssertEqual(series[0].points.map(\.remainingPercent), [80, 70])
        XCTAssertEqual(series[1].points.map(\.remainingPercent), [95])
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

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].points.map(\.remainingPercent), [85])
    }

    func testKeepsMinimumSamplePerBucketAndWindowEdges() {
        let reset = start.addingTimeInterval(7 * 86_400)
        let bucket: TimeInterval = 1_800
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 100, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 98, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(1_200), remainingPercent: 96, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(2_000), remainingPercent: 94, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(2_400), remainingPercent: 92, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(4_000), remainingPercent: 90, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: bucket
        )

        XCTAssertEqual(series.count, 1)
        XCTAssertEqual(series[0].points.map(\.remainingPercent), [100, 96, 92, 90])
        XCTAssertEqual(series[0].points.first?.date, start)
        XCTAssertEqual(series[0].points.last?.date, start.addingTimeInterval(4_000))
    }

    func testKeepsSparseWindowsWithoutDownsampling() {
        let reset = start.addingTimeInterval(86_400)
        let samples = [
            UsageSample(observedAt: start.addingTimeInterval(60), remainingPercent: 88, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(120), remainingPercent: 86, resetsAt: reset)
        ]

        let series = HistorySeriesBuilder.series(
            from: samples,
            in: start ... reset,
            bucketDuration: 1_800
        )

        XCTAssertEqual(series[0].points.map(\.remainingPercent), [88, 86])
    }

    func testEmptyInputProducesNoSeries() {
        let series = HistorySeriesBuilder.series(
            from: [],
            in: start ... start.addingTimeInterval(86_400),
            bucketDuration: 1_800
        )

        XCTAssertTrue(series.isEmpty)
    }
}
