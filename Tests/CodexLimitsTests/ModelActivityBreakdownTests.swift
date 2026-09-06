import XCTest
@testable import CodexLimits

final class ModelActivityBreakdownTests: XCTestCase {
    func testModelTotalsCombineEffortsAndDrilldownStaysWithinModel() {
        let breakdown = ModelActivityBreakdown(contributions: [
            contribution("a", "high", 20), contribution("a", "low", 30),
            contribution("b", "high", 100), contribution("a", "high", 10)
        ])
        XCTAssertEqual(breakdown.models, [.init(name: "b", tokens: 100), .init(name: "a", tokens: 60)])
        XCTAssertEqual(breakdown.efforts(for: "a"), [.init(name: "high", tokens: 30), .init(name: "low", tokens: 30)])
        XCTAssertEqual(breakdown.efforts(for: "missing"), [])
        XCTAssertEqual(breakdown.efforts(for: "b").reduce(0) { $0 + $1.tokens }, 100)
    }

    func testZeroTokensDoNotCreateSlicesAndSelectionUsesCumulativeBoundaries() {
        let breakdown = ModelActivityBreakdown(contributions: [
            contribution("a", "high", 0), contribution("b", "low", 30), contribution("c", "low", 10)
        ])
        XCTAssertEqual(breakdown.models.count, 2)
        XCTAssertEqual(ModelActivityBreakdown.slice(at: 0, in: breakdown.models), "b")
        XCTAssertEqual(ModelActivityBreakdown.slice(at: 29.9, in: breakdown.models), "b")
        XCTAssertEqual(ModelActivityBreakdown.slice(at: 30, in: breakdown.models), "c")
        for angle: Double? in [nil, -1, 40, .nan, .infinity] {
            XCTAssertNil(ModelActivityBreakdown.slice(at: angle, in: breakdown.models))
        }
        XCTAssertEqual(breakdown.efforts(for: "a"), [])
    }

    func testBreakdownUsesChosenMetricAndKeepsUnmatchedModelsForContext() {
        let start = Date(timeIntervalSince1970: 0)
        let events = [ModelActivityEvent(id: "1", date: start, group: .init(model: "a", effort: "high"),
                                        tokens: .init(input: 80, output: 20, cached: 0, total: 100))]
        let timeline = ModelActivityTimeline(events: events, range: start ... start.addingTimeInterval(3600),
                                             intervalDuration: 3600, metric: .output, models: [], efforts: [])
        let breakdown = ModelActivityBreakdown(contributions: timeline.intervals[0].contributions)
        XCTAssertEqual(timeline.matched, 0)
        XCTAssertEqual(breakdown.models, [.init(name: "a", tokens: 20)])
    }

    private func contribution(_ model: String, _ effort: String, _ tokens: Int64) -> ModelActivityTimeline.Contribution {
        .init(group: .init(model: model, effort: effort), tokens: tokens, events: 1)
    }
}
