import XCTest
@testable import CodexLimits

final class ModelActivityTimelineTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_783_382_400)

    func testIntervalsUseHalfOpenBoundariesAndKeepEmptyPeriods() {
        let events = [event(0, "a", "high", 10), event(3_599, "a", "high", 20),
                      event(3_600, "b", "low", 40), event(10_800, "b", "low", 1_000)]
        let timeline = make(events)
        XCTAssertEqual(timeline.intervals.map(\.total), [30, 40, 0])
        XCTAssertEqual(timeline.total, 70)
        XCTAssertEqual(timeline.activeIntervals, 2)
        XCTAssertEqual(timeline.interval(at: start.addingTimeInterval(3_600))?.total, 40)
        XCTAssertEqual(timeline.interval(at: nil)?.total, 40)
    }

    func testModelAndEffortFiltersIntersectWithoutChangingTotalOrContributions() {
        let events = [event(1, "a", "high", 10), event(2, "a", "low", 20), event(3, "b", "high", 30)]
        let timeline = make(events, models: ["a"], efforts: ["high"])
        XCTAssertEqual(timeline.total, 60)
        XCTAssertEqual(timeline.matched, 10)
        XCTAssertEqual(timeline.intervals[0].contributions.count, 3)
        XCTAssertEqual(timeline.matchingIntervals, 1)
        XCTAssertEqual(make(events, models: []).matched, 0)
        XCTAssertEqual(make(events, efforts: []).matchingIntervals, 0)
    }

    func testOutputMetricDoesNotCountInputTokensOrDoubleCountEvents() {
        let events = [event(1, "a", "high", 100), event(2, "a", "high", 200)]
        let timeline = make(events, metric: .output)
        XCTAssertEqual(timeline.total, 30)
        XCTAssertEqual(timeline.intervals[0].contributions.first?.events, 2)
        XCTAssertEqual(timeline.intervals[0].contributions.count, 1)
    }

    func testPartialIntervalsAreClippedToTheSelectedRange() {
        let lower = start.addingTimeInterval(900)
        let upper = start.addingTimeInterval(4_500)
        let timeline = ModelActivityTimeline(events: [event(899, "a", "high", 10), event(900, "a", "high", 20)],
            range: lower ... upper, intervalDuration: 3_600, metric: .total, models: nil, efforts: nil)
        XCTAssertEqual(timeline.intervals.count, 2)
        XCTAssertEqual(timeline.intervals.first?.start, lower)
        XCTAssertEqual(timeline.intervals.last?.end, upper)
        XCTAssertEqual(timeline.total, 20)
    }

    func testMatchingHighlightsMergeAdjacentIntervalsAndRetainZeroOutputActivity() {
        let events = [event(1, "a", "high", 1), event(3_601, "a", "high", 1), event(7_201, "b", "low", 10)]
        let timeline = make(events, models: ["a"], metric: .output)
        XCTAssertEqual(timeline.matched, 0)
        XCTAssertEqual(timeline.matchingIntervals, 2)
        XCTAssertEqual(timeline.highlights.count, 1)
        XCTAssertEqual(timeline.highlights.first?.start, start)
        XCTAssertEqual(timeline.highlights.first?.end, start.addingTimeInterval(7_200))
    }

    func testSelectedModelSegmentsStackOnlyMatchingTokensAndKeepStableLanes() {
        let events = [event(1, "b", "high", 30), event(2, "a", "high", 10),
                      event(3, "a", "low", 20), event(3_601, "b", "high", 40)]
        let timeline = make(events, efforts: ["high"])
        XCTAssertEqual(timeline.matchedModels, ["a", "b"])
        XCTAssertEqual(timeline.modelSegments.map(\.model), ["a", "b", "b"])
        XCTAssertEqual(timeline.modelSegments.map(\.lower), [0, 10, 0])
        XCTAssertEqual(timeline.modelSegments.map(\.upper), [10, 40, 40])
        XCTAssertEqual(timeline.modelSegments.map(\.lane), [0, 1, 1])
        XCTAssertEqual(timeline.modelSegments.reduce(0) { $0 + $1.upper - $1.lower }, timeline.matched)
        let filtered = make(events, models: ["b"])
        XCTAssertEqual(filtered.modelSegments.map(\.model), ["b", "b"])
        XCTAssertEqual(filtered.modelSegments.map(\.lower), [0, 0])
        XCTAssertTrue(make(events, models: []).modelSegments.isEmpty)
    }

    func testZeroOutputStillProducesModelPresenceBand() {
        let timeline = make([event(1, "a", "high", 1)], metric: .output)
        XCTAssertEqual(timeline.modelSegments.count, 1)
        XCTAssertEqual(timeline.modelSegments[0].upper, 0)
        XCTAssertEqual(timeline.modelSegments[0].model, "a")
    }

    private func make(_ events: [ModelActivityEvent], models: Set<String>? = nil, efforts: Set<String>? = nil,
                      metric: ModelActivityTimeline.Metric = .total) -> ModelActivityTimeline {
        ModelActivityTimeline(events: events, range: start ... start.addingTimeInterval(10_800),
                              intervalDuration: 3_600, metric: metric, models: models, efforts: efforts)
    }

    private func event(_ seconds: TimeInterval, _ model: String, _ effort: String, _ total: Int64) -> ModelActivityEvent {
        .init(id: "\(seconds)", date: start.addingTimeInterval(seconds), group: .init(model: model, effort: effort),
              tokens: .init(input: total * 9 / 10, output: total / 10, cached: 0, total: total))
    }
}
