import XCTest
@testable import CodexLimits

final class ModelActivityStoreTests: XCTestCase {
    @MainActor func testBurndownFollowsPeriodWhileFiltersKeepTheObservedCurve() {
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let store = ModelActivityStore(now: now)
        let samples = [
            UsageSample(observedAt: now.addingTimeInterval(-2 * 86_400), remainingPercent: 90, resetsAt: now.addingTimeInterval(86_400)),
            UsageSample(observedAt: now.addingTimeInterval(-600), remainingPercent: 70, resetsAt: now.addingTimeInterval(86_400))
        ]
        store.updateHistory(samples)
        let fullHistory = store.history.series
        XCTAssertEqual(fullHistory.runs.flatMap(\.points).count, 2)
        store.selectedModels = []
        store.selectedEfforts = ["high"]
        store.metric = .output
        XCTAssertEqual(store.history.series, fullHistory, "Filters highlight the history; they must not remove the actual usage curve")
        store.updateWindow(UsageWindow(remainingPercent: 70, resetsAt: now, durationMinutes: 1440))
        store.days = 0
        XCTAssertEqual(store.history.series.runs.flatMap(\.points).count, 1)
        XCTAssertEqual(store.history.series.latestPoint?.remainingPercent, 70)
        store.days = 7
        XCTAssertEqual(store.history.series, fullHistory)
    }
    @MainActor func testUnhoveredSummaryUsesWholeVisibleRangeAndExactPartialBoundaries() {
        let now = Date(timeIntervalSince1970: 30 * 86_400)
        let lower = now.addingTimeInterval(-20 * 86_400 + 123)
        let upper = lower.addingTimeInterval(7 * 86_400)
        let events = [event(lower.addingTimeInterval(-1), 1000), event(lower, 10),
                      event(upper.addingTimeInterval(-1), 20), event(upper, 2000), event(now.addingTimeInterval(-1), 30)]
        let store = ModelActivityStore(previewEvents: events, now: now)
        XCTAssertEqual(store.detail(at: nil).total, 30)
        store.viewport.position = lower
        // A filter rebuild uses the current viewport immediately (scroll-only changes are coalesced).
        store.selectedModels = nil
        XCTAssertEqual(store.detail(at: nil).start, lower)
        XCTAssertEqual(store.detail(at: nil).end, upper)
        XCTAssertEqual(store.detail(at: nil).total, 30)
        XCTAssertEqual(store.detail(at: nil).contributions.first?.events, 2)
        XCTAssertEqual(store.detail(at: lower).total, 10)
        XCTAssertEqual(store.detail(at: nil).total, 30, "Leaving hover restores the full range")
        store.selectedModels = []
        XCTAssertEqual(store.detail(at: nil).matched, 0)
        XCTAssertEqual(store.detail(at: nil).total, 0)
        XCTAssertTrue(store.detail(at: nil).contributions.isEmpty)
        store.selectedModels = nil
        store.days = 30
        XCTAssertEqual(store.detail(at: nil).total, 3060)
    }

    @MainActor func testWindowUsesActualResetBoundsAndResetsViewportWhenChangingPeriods() {
        let now = Date(timeIntervalSince1970: 30 * 86_400)
        let store = ModelActivityStore(previewEvents: [event(now.addingTimeInterval(-2 * 86_400), 10),
                                                      event(now.addingTimeInterval(-600), 20)], now: now)
        let window = UsageWindow(remainingPercent: 80, resetsAt: now.addingTimeInterval(86_400), durationMinutes: 2 * 1440)
        store.updateWindow(window)
        store.days = 0
        XCTAssertEqual(store.visibleTimeline.range, window.startsAt ... window.resetsAt)
        XCTAssertEqual(store.detail(at: nil).total, 20)
        XCTAssertNil(store.viewport.visibleDuration)
        store.days = 7
        XCTAssertEqual(store.visibleTimeline.range, now.addingTimeInterval(-7 * 86_400) ... now)
        XCTAssertEqual(store.detail(at: nil).total, 30)
    }

    @MainActor func testModelAndEffortFiltersControlBothPieLevelsAndIntervalDetails() {
        let now = Date(timeIntervalSince1970: 30 * 86_400)
        let events = [
            ModelActivityEvent(id: "1", date: now.addingTimeInterval(-30), group: .init(model: "a", effort: "high"), tokens: .init(input: 10, output: 0, cached: 0, total: 10)),
            ModelActivityEvent(id: "2", date: now.addingTimeInterval(-20), group: .init(model: "a", effort: "low"), tokens: .init(input: 20, output: 0, cached: 0, total: 20)),
            ModelActivityEvent(id: "3", date: now.addingTimeInterval(-10), group: .init(model: "b", effort: "high"), tokens: .init(input: 70, output: 0, cached: 0, total: 70))
        ]
        let store = ModelActivityStore(previewEvents: events, now: now)
        store.selectedModels = ["a"]
        var pie = ModelActivityBreakdown(contributions: store.detail(at: nil).contributions)
        XCTAssertEqual(pie.models, [.init(name: "a", tokens: 30)])
        XCTAssertEqual(pie.efforts(for: "a").count, 2)
        store.selectedEfforts = ["high"]
        pie = ModelActivityBreakdown(contributions: store.detail(at: nil).contributions)
        XCTAssertEqual(pie.models, [.init(name: "a", tokens: 10)])
        XCTAssertEqual(pie.efforts(for: "a"), [.init(name: "high", tokens: 10)])
        XCTAssertEqual(store.detail(at: events[0].date).total, 10)
        XCTAssertEqual(store.visibleTimeline.total, 100, "Account context remains available for the selected-share statistic")
        store.selectedEfforts = []
        XCTAssertTrue(store.detail(at: nil).contributions.isEmpty)
        XCTAssertTrue(store.timeline.modelSegments.isEmpty)
    }

    private func event(_ date: Date, _ tokens: Int64) -> ModelActivityEvent {
        .init(id: date.description, date: date, group: .init(model: "a", effort: "high"),
              tokens: .init(input: tokens, output: 0, cached: 0, total: tokens))
    }

}
