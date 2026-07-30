import XCTest
@testable import CodexLimits

final class ChartRangeTests: XCTestCase {
    func testTitles() {
        XCTAssertEqual(ChartRange.window.title, "Window")
        XCTAssertEqual(ChartRange.week.title, "7 days")
        XCTAssertEqual(ChartRange.month.title, "30 days")
    }

    func testHistoryRangesShareTheSameDataDomainAndBuckets() {
        XCTAssertNil(ChartRange.window.duration)
        XCTAssertEqual(ChartRange.week.duration, 30 * 86_400)
        XCTAssertEqual(ChartRange.month.duration, 30 * 86_400)
        XCTAssertEqual(ChartRange.week.bucketDuration, ChartRange.month.bucketDuration)
        XCTAssertEqual(ChartRange.week.bucketDuration, 1_800)
    }

    func testOnlyTheWeekRangeScrolls() {
        XCTAssertNil(ChartRange.window.visibleDuration)
        XCTAssertEqual(ChartRange.week.visibleDuration, 7 * 86_400)
        XCTAssertNil(ChartRange.month.visibleDuration)
    }
}
