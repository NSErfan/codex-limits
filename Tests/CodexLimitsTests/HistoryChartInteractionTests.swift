import Combine
import XCTest
@testable import CodexLimits

final class HistoryChartInteractionTests: XCTestCase {
    @MainActor func testScrollingClearsSelectionOnceAndSuppressesRepeatedPointerUpdates() {
        let interaction = HistoryChartInteraction()
        let date = Date(timeIntervalSince1970: 1_000_000)
        interaction.select(date, at: 0)
        var changes = 0
        let subscription = interaction.objectWillChange.sink { changes += 1 }

        for step in 0 ..< 360 {
            let time = Double(step) / 120
            interaction.scroll(at: time)
            interaction.select(date.addingTimeInterval(Double(step)), at: time + 0.001)
        }

        XCTAssertNil(interaction.selectedDate)
        XCTAssertEqual(changes, 1)
        withExtendedLifetime(subscription) {}
    }

    @MainActor func testHoverResumesAfterTheLastScrollSettles() {
        let interaction = HistoryChartInteraction()
        let date = Date(timeIntervalSince1970: 1_000_000)
        interaction.scroll(at: 1)
        interaction.scroll(at: 1.1)
        interaction.select(date, at: 1.24)
        XCTAssertNil(interaction.selectedDate)

        interaction.select(date, at: 1.26)
        XCTAssertEqual(interaction.selectedDate, date)
        interaction.select(nil, at: 1.27)
        XCTAssertNil(interaction.selectedDate)
    }

    @MainActor func testUnchangedHoverDoesNotPublishAnotherChartUpdate() {
        let interaction = HistoryChartInteraction()
        let date = Date(timeIntervalSince1970: 1_000_000)
        var changes = 0
        let subscription = interaction.objectWillChange.sink { changes += 1 }

        interaction.select(date, at: 0)
        interaction.select(date, at: 0.01)
        interaction.select(nil, at: 0.02)
        interaction.select(nil, at: 0.03)

        XCTAssertEqual(changes, 2)
        withExtendedLifetime(subscription) {}
    }
}
