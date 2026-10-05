import Foundation
import XCTest
@testable import CodexWidgetKit

final class WeeklyWidgetTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testSchedulesBothProvidersStalenessAndResetIndependently() {
        let codex = snapshot(fetchedAt: now, reset: now.addingTimeInterval(1_200))
        let claude = snapshot(fetchedAt: now.addingTimeInterval(-600), reset: now.addingTimeInterval(86_400))
        let dates = WeeklyWidgetTimeline.entryDates(for: [codex, claude], at: now)

        XCTAssertEqual(dates, [0, 300, 600, 900, 1_200, 1_800, 86_400].map { now.addingTimeInterval($0) })
        XCTAssertEqual(codex.status(at: now.addingTimeInterval(1_200)), .expired)
        XCTAssertEqual(claude.status(at: now.addingTimeInterval(1_200)), .stale)
    }

    func testMissingOrExpiredReadingsOnlyScheduleNow() {
        XCTAssertEqual(WeeklyWidgetTimeline.entryDates(for: [], at: now), [now])
        let expired = snapshot(fetchedAt: now.addingTimeInterval(-3_600), reset: now.addingTimeInterval(-1))
        XCTAssertEqual(WeeklyWidgetTimeline.entryDates(for: [expired], at: now), [now])
    }

    private func snapshot(fetchedAt: Date, reset: Date) -> WeeklyWidgetSnapshot {
        WeeklyWidgetSnapshot(fetchedAt: fetchedAt, window: .init(
            remainingPercent: 68, startsAt: reset.addingTimeInterval(-7 * 86_400), resetsAt: reset
        ), reservePercent: 3)
    }
}
