import XCTest
@testable import CodexLimits

final class PaceTargetTests: XCTestCase {
    func testTargetRunsFromFullBalanceToConfiguredReserve() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        for span: TimeInterval in [1, 60, 5 * 3_600, 7 * 86_400] {
            for reserve in [1.0, 3, 10] {
                let target = PaceTarget(startsAt: start, deadline: start.addingTimeInterval(span), reservePercent: reserve)

                XCTAssertEqual(target.remainingPercent(at: start), 100)
                XCTAssertEqual(target.remainingPercent(at: start.addingTimeInterval(span / 2)), (100 + reserve) / 2)
                XCTAssertEqual(target.remainingPercent(at: target.deadline), reserve)
                XCTAssertEqual(target.remainingPercent(at: start.addingTimeInterval(-1)), 100)
                XCTAssertEqual(target.remainingPercent(at: target.deadline.addingTimeInterval(1)), reserve)
            }
        }
    }

    func testExpiredOrEmptySpanDoesNotProduceInvalidPercentages() {
        let date = Date(timeIntervalSince1970: 1_000_000)
        for offset: TimeInterval in [-1, 0] {
            let target = PaceTarget(startsAt: date, deadline: date.addingTimeInterval(offset), reservePercent: 3)
            XCTAssertEqual(target.remainingPercent(at: date), 3)
        }
    }
}
