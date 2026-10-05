import Foundation
import XCTest
@testable import CodexWidgetKit

final class AllowancePaceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSpreadsSpendableBalanceAcrossTimeUntilReset() throws {
        let rate = try XCTUnwrap(AllowancePace.dailyPercent(
            remainingPercent: 68, reservePercent: 3, resetsAt: now.addingTimeInterval(4 * 86_400), date: now
        ))
        XCTAssertEqual(rate, 16.25, accuracy: 0.0001)
    }

    func testPaceNearResetUsesTheActualFractionOfADay() throws {
        let rate = try XCTUnwrap(AllowancePace.dailyPercent(
            remainingPercent: 10, reservePercent: 3, resetsAt: now.addingTimeInterval(12 * 3_600), date: now
        ))
        XCTAssertEqual(rate, 14, accuracy: 0.0001)
        XCTAssertEqual(AllowancePace.dailyPercent(remainingPercent: 2, reservePercent: 3,
                                                 resetsAt: now.addingTimeInterval(86_400), date: now), 0)
    }

    func testInvalidBalancesAndPassedResetsHaveNoSuggestedPace() {
        for remaining in [Double.nan, .infinity, -1, 101] {
            XCTAssertNil(AllowancePace.dailyPercent(remainingPercent: remaining, reservePercent: 3,
                                                   resetsAt: now.addingTimeInterval(86_400), date: now))
        }
        for reserve in [Double.nan, .infinity, -1, 101] {
            XCTAssertNil(AllowancePace.dailyPercent(remainingPercent: 68, reservePercent: reserve,
                                                   resetsAt: now.addingTimeInterval(86_400), date: now))
        }
        for reset in [now, now.addingTimeInterval(-1)] {
            XCTAssertNil(AllowancePace.dailyPercent(remainingPercent: 68, reservePercent: 3, resetsAt: reset, date: now))
        }
    }
}
