import XCTest
@testable import CodexLimits

final class ChartInteractionTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_000_000)

    func testNearestPicksTheClosestItem() {
        let dates = [base, base.addingTimeInterval(600), base.addingTimeInterval(3_600)]

        let nearest = ChartInteraction.nearest(
            to: base.addingTimeInterval(500),
            in: dates,
            date: { $0 }
        )

        XCTAssertEqual(nearest, base.addingTimeInterval(600))
    }

    func testNearestOfNothingIsNil() {
        XCTAssertNil(ChartInteraction.nearest(to: base, in: [Date](), date: { $0 }))
    }

    func testToleranceAcceptsCloseAndRejectsFarTargets() {
        let span: TimeInterval = 7 * 86_400
        let tolerance = span * ChartInteraction.hoverToleranceFraction
        let reset = base.addingTimeInterval(3 * 86_400)

        let hit = ChartInteraction.nearest(
            to: reset.addingTimeInterval(tolerance - 1),
            in: [reset],
            visibleSpan: span,
            date: { $0 }
        )
        let miss = ChartInteraction.nearest(
            to: reset.addingTimeInterval(tolerance + 1),
            in: [reset],
            visibleSpan: span,
            date: { $0 }
        )

        XCTAssertEqual(hit, reset)
        XCTAssertNil(miss)
    }
}
