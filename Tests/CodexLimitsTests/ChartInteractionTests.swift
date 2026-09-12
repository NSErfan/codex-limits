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

    func testNearestResetCreditUsesTheChartHitTolerance() {
        let window = UsageWindow(
            remainingPercent: 50,
            resetsAt: base.addingTimeInterval(7 * 86_400),
            durationMinutes: 7 * 24 * 60
        )
        let expiry = base.addingTimeInterval(3 * 86_400)
        let credit = ResetCredit(
            id: "credit",
            title: nil,
            expiresAt: expiry
        )
        let tolerance = 7 * 86_400 * ChartInteraction.hoverToleranceFraction

        XCTAssertEqual(
            ChartInteraction.nearestResetCredit(
                to: expiry.addingTimeInterval(tolerance - 1),
                in: [credit],
                window: window
            ),
            credit
        )
        XCTAssertNil(ChartInteraction.nearestResetCredit(
            to: expiry.addingTimeInterval(tolerance + 1),
            in: [credit],
            window: window
        ))
    }

    func testCreditTapTogglesTheSelection() {
        let credit = ResetCredit(id: "credit", title: nil, expiresAt: base)

        XCTAssertEqual(ChartInteraction.toggledCreditID(current: "", tapped: credit), "credit")
        XCTAssertEqual(ChartInteraction.toggledCreditID(current: "other", tapped: credit), "credit")
        XCTAssertEqual(ChartInteraction.toggledCreditID(current: "credit", tapped: credit), "")
    }

    func testTargetTapSelectsMovesAndClearsWithinTheChartHitTolerance() {
        for span: TimeInterval in [5 * 3_600, 7 * 86_400] {
            let target = base.addingTimeInterval(span / 2)
            let tolerance = span * ChartInteraction.hoverToleranceFraction
            XCTAssertEqual(ChartInteraction.toggledTargetDate(current: nil, tapped: target, visibleSpan: span), target)
            for offset in [-tolerance, 0, tolerance] {
                XCTAssertNil(ChartInteraction.toggledTargetDate(
                    current: target, tapped: target.addingTimeInterval(offset), visibleSpan: span
                ))
            }
            for offset in [-tolerance - 1, tolerance + 1] {
                let other = target.addingTimeInterval(offset)
                XCTAssertEqual(ChartInteraction.toggledTargetDate(
                    current: target, tapped: other, visibleSpan: span
                ), other)
            }
        }
    }
}
