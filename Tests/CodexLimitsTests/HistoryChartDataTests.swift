import XCTest
@testable import CodexLimits

final class HistoryChartDataTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_789_000_000)

    func testSimplificationKeepsTheCurveAndResetCorners() {
        let levels = [90.0, 90, 90, 88, 86, 84, 84, 84, 100, 100, 100, 98]
        let points = levels.enumerated().map { point($0.offset, $0.element) }
        let reduced = HistoryChartData.simplified(points)
        XCTAssertLessThan(reduced.count, points.count)
        XCTAssertEqual(reduced.first, points.first)
        XCTAssertEqual(reduced.last, points.last)
        for point in points {
            let upper = reduced.firstIndex { $0.date >= point.date }!
            if upper == 0 {
                XCTAssertEqual(point.remainingPercent, reduced[0].remainingPercent)
                continue
            }
            let before = reduced[upper - 1]
            let after = reduced[upper]
            let fraction = point.date.timeIntervalSince(before.date) / after.date.timeIntervalSince(before.date)
            let rendered = before.remainingPercent + fraction * (after.remainingPercent - before.remainingPercent)
            XCTAssertEqual(rendered, point.remainingPercent, accuracy: 1e-9)
        }
    }

    func testSparseDrawingsKeepOriginalHoverReadingsAndTieOrder() {
        let data = makeData(levels: [80, 80, 80, 80, 80])
        XCTAssertEqual(data.plotRuns[0].points.count, 2)
        XCTAssertEqual(data.series.runs[0].points.count, 5)
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(1_200), visibleSpan: 7 * 86_400), .point(point(2, 80)))
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(1_500), visibleSpan: 7 * 86_400), .point(point(2, 80)))
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(-600), visibleSpan: 7 * 86_400), .point(point(0, 80)))
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(10_000), visibleSpan: 7 * 86_400), .point(point(4, 80)))
    }

    func testGapAndResetSelectionRetainPriorityAndBoundaries() {
        let reset = start.addingTimeInterval(86_400)
        let samples = [
            UsageSample(observedAt: start, remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: start.addingTimeInterval(600), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: reset, remainingPercent: 100, resetsAt: reset.addingTimeInterval(7 * 86_400))
        ]
        let data = HistoryChartData(samples: samples, range: start ... reset.addingTimeInterval(600), bucketDuration: 0)
        XCTAssertEqual(data.plotRuns.count, 2)
        XCTAssertEqual(data.series.connectors.count, 1)
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(600), visibleSpan: 86_400), .point(point(1, 80)))
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(3_600), visibleSpan: 86_400), .gap)
        XCTAssertEqual(data.selection(at: reset, visibleSpan: 86_400), .reset(reset))
        XCTAssertEqual(data.selection(at: reset.addingTimeInterval(-60), visibleSpan: 86_400), .reset(reset))
    }

    func testBatchPlotsConnectGapsWithoutFillingThemAsSampled() {
        let offsets = [0.0, 600, 1_200, 7_200, 7_800, 14_400]
        let levels = [90.0, 90, 88, 80, 80, 70]
        let end = start.addingTimeInterval(20_000)
        let samples = zip(offsets, levels).map { offset, level in
            UsageSample(observedAt: start.addingTimeInterval(offset), remainingPercent: level, resetsAt: end)
        }
        let data = HistoryChartData(samples: samples, range: start ... end, bucketDuration: 0)
        XCTAssertEqual(data.linePoints, data.plotRuns.flatMap(\.points))
        XCTAssertEqual(data.linePoints.map(\.date), offsets.map { start.addingTimeInterval($0) })
        let sampled = Dictionary(grouping: data.sampledArea, by: \.seriesID)
        XCTAssertEqual(sampled.count, 3)
        for run in data.plotRuns {
            XCTAssertEqual(sampled["run-\(run.id)"]?.map(\.date), run.points.map(\.date))
            XCTAssertEqual(sampled["run-\(run.id)"]?.map(\.remainingPercent), run.points.map(\.remainingPercent))
        }
        let gaps = Dictionary(grouping: data.gapArea, by: \.seriesID)
        XCTAssertEqual(gaps.count, 2)
        XCTAssertTrue(Set(sampled.keys).isDisjoint(with: Set(gaps.keys)))
        for connector in data.series.connectors {
            XCTAssertEqual(gaps["gap-\(connector.id)"]?.map(\.date), [connector.start.date, connector.end.date])
            XCTAssertEqual(gaps["gap-\(connector.id)"]?.map(\.remainingPercent), [connector.start.remainingPercent, connector.end.remainingPercent])
        }
    }

    func testDenseFlatHistoryHasBoundedDrawingCost() {
        let data = makeData(levels: Array(repeating: 75, count: 4_321))
        XCTAssertEqual(data.series.runs[0].points.count, 4_321)
        XCTAssertEqual(data.plotRuns[0].points.count, 2)
        XCTAssertEqual(data.selection(at: start.addingTimeInterval(300 * 600), visibleSpan: 7 * 86_400), .point(point(300, 75)))
    }

    func testMonthOfStepwiseReadingsReducesDrawingWork() {
        let end = start.addingTimeInterval(30 * 86_400)
        let samples = (0 ... 4_320).map { index in
            UsageSample(
                observedAt: start.addingTimeInterval(Double(index) * 600),
                remainingPercent: 100 - Double((index % 1_008) / 12),
                resetsAt: end
            )
        }
        let data = HistoryChartData(samples: samples, range: start ... end, bucketDuration: 1_800)
        let before = data.series.runs.reduce(0) { $0 + $1.points.count }
        let after = data.plotRuns.reduce(0) { $0 + $1.points.count }
        XCTAssertLessThan(Double(after), Double(before) * 0.55)
        XCTAssertEqual(data.series.latestPoint, data.plotRuns.last?.points.last)
        print("History drawing: \(before) → \(after) points; all \(before) hover readings retained")
    }

    func testEmptyHistoryHasNoSelectionOrDrawing() {
        let data = makeData(levels: [])
        XCTAssertTrue(data.plotRuns.isEmpty)
        XCTAssertNil(data.selection(at: start, visibleSpan: 86_400))
        XCTAssertNil(data.selection(at: nil, visibleSpan: 86_400))
    }

    private func makeData(levels: [Double]) -> HistoryChartData {
        let end = start.addingTimeInterval(Double(max(levels.count, 1)) * 600)
        let samples = levels.enumerated().map { index, level in
            UsageSample(observedAt: start.addingTimeInterval(Double(index) * 600), remainingPercent: level, resetsAt: end)
        }
        return HistoryChartData(samples: samples, range: start ... end, bucketDuration: 0)
    }

    private func point(_ index: Int, _ remaining: Double) -> HistorySeriesBuilder.Point {
        .init(date: start.addingTimeInterval(Double(index) * 600), remainingPercent: remaining)
    }
}
