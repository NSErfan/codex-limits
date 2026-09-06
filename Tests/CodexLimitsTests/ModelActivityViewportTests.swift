import XCTest
@testable import CodexLimits

final class ModelActivityViewportTests: XCTestCase {
    @MainActor func testViewportClampsAtBothEndsAndTracksLatestOnlyWhenAlreadyAtLatest() {
        let start = Date(timeIntervalSince1970: 0)
        let end = start.addingTimeInterval(30 * 86_400)
        let viewport = ModelActivityViewport(range: start ... end, visibleDuration: 7 * 86_400)
        XCTAssertEqual(viewport.visibleRange, end.addingTimeInterval(-7 * 86_400) ... end)
        viewport.position = start.addingTimeInterval(-100)
        XCTAssertEqual(viewport.visibleRange, start ... start.addingTimeInterval(7 * 86_400))
        viewport.position = end
        XCTAssertEqual(viewport.visibleRange.upperBound, end)
        viewport.position = start.addingTimeInterval(5 * 86_400)
        viewport.configure(range: start.addingTimeInterval(60) ... end.addingTimeInterval(60), visibleDuration: 7 * 86_400, reset: false)
        XCTAssertEqual(viewport.position, start.addingTimeInterval(5 * 86_400))
        viewport.configure(range: start ... end, visibleDuration: 7 * 86_400, reset: true)
        viewport.configure(range: start.addingTimeInterval(60) ... end.addingTimeInterval(60), visibleDuration: 7 * 86_400, reset: false)
        XCTAssertEqual(viewport.visibleRange.upperBound, end.addingTimeInterval(60))
        viewport.configure(range: start ... end, visibleDuration: nil, reset: true)
        XCTAssertEqual(viewport.visibleRange, start ... end)
    }

    @MainActor func testScrollingCoalescesRangeSummaryUpdates() async {
        let start = Date(timeIntervalSince1970: 0)
        let viewport = ModelActivityViewport(range: start ... start.addingTimeInterval(30 * 86_400), visibleDuration: 7 * 86_400)
        let updated = expectation(description: "Settled range")
        updated.assertForOverFulfill = true
        viewport.onRangeChange = { range in
            XCTAssertEqual(range.lowerBound, start.addingTimeInterval(99))
            updated.fulfill()
        }
        for second in 0 ... 99 { viewport.position = start.addingTimeInterval(Double(second)) }
        await fulfillment(of: [updated], timeout: 2)
    }
}
