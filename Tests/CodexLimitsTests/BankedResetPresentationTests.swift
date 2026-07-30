import XCTest
@testable import CodexLimits

final class BankedResetPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_785_000_000)
    private let windowReset = Date(timeIntervalSince1970: 1_785_911_168)

    func testQualificationRequiresFutureExpiryBeforeTheWindowReset() {
        func credit(_ expiresAt: Date?) -> ResetCredit {
            ResetCredit(id: "credit", title: nil, expiresAt: expiresAt)
        }

        XCTAssertTrue(BankedResetPresentation.qualifies(
            credit(now.addingTimeInterval(3_600)), now: now, windowReset: windowReset
        ))
        XCTAssertFalse(BankedResetPresentation.qualifies(
            credit(now.addingTimeInterval(-3_600)), now: now, windowReset: windowReset
        ))
        XCTAssertFalse(BankedResetPresentation.qualifies(
            credit(windowReset.addingTimeInterval(3_600)), now: now, windowReset: windowReset
        ))
        XCTAssertFalse(BankedResetPresentation.qualifies(
            credit(nil), now: now, windowReset: windowReset
        ))
    }

    func testLabelLeadsWithSoonestExpiryAndCountsTheRest() {
        let soon = Date(timeIntervalSince1970: 1_785_100_000)
        let later = Date(timeIntervalSince1970: 1_786_000_000)
        let credits = [
            ResetCredit(id: "later", title: nil, expiresAt: later),
            ResetCredit(id: "soon", title: nil, expiresAt: soon)
        ]

        let parts = BankedResetPresentation.labelParts(for: credits)

        XCTAssertEqual(parts.head, BankedResetPresentation.dateText(soon))
        XCTAssertEqual(parts.extra, "+1 more")
    }

    func testSingleCreditLabelHasNoExtraCount() {
        let credits = [ResetCredit(id: "only", title: nil, expiresAt: now)]

        let parts = BankedResetPresentation.labelParts(for: credits)

        XCTAssertEqual(parts.head, BankedResetPresentation.dateText(now))
        XCTAssertNil(parts.extra)
    }

    func testLabelWithoutAnyExpiryDates() {
        let parts = BankedResetPresentation.labelParts(
            for: [ResetCredit(id: "open-ended", title: nil, expiresAt: nil)]
        )

        XCTAssertEqual(parts.head, "No expiry")
        XCTAssertNil(parts.extra)
    }

    func testItemTextIncludesTitleExpiryAndAfterResetSuffix() {
        let inWindow = ResetCredit(
            id: "in",
            title: "Full reset",
            expiresAt: windowReset.addingTimeInterval(-3_600)
        )
        let afterReset = ResetCredit(
            id: "after",
            title: "Full reset",
            expiresAt: windowReset.addingTimeInterval(3_600)
        )
        let openEnded = ResetCredit(id: "open", title: nil, expiresAt: nil)

        XCTAssertEqual(
            BankedResetPresentation.itemText(inWindow, windowReset: windowReset),
            "Full reset · expires \(BankedResetPresentation.dateText(inWindow.expiresAt))"
        )
        XCTAssertEqual(
            BankedResetPresentation.itemText(afterReset, windowReset: windowReset),
            "Full reset · expires \(BankedResetPresentation.dateText(afterReset.expiresAt)) · after the next reset"
        )
        XCTAssertEqual(
            BankedResetPresentation.itemText(openEnded, windowReset: windowReset),
            "Banked reset · no expiry"
        )
    }

    func testHintExplainsHowToEnterAndLeaveTheMode() {
        XCTAssertEqual(
            BankedResetPresentation.hint(hasSelection: false),
            "Pick a banked reset to pace toward its expiry."
        )
        XCTAssertEqual(
            BankedResetPresentation.hint(hasSelection: true),
            "Pick the checked reset again to pace to the window reset."
        )
    }

    func testDateTextUsesFixedLocaleAndHandlesNil() {
        XCTAssertEqual(BankedResetPresentation.dateText(nil), "no expiry")
        let text = BankedResetPresentation.dateText(Date(timeIntervalSince1970: 1_785_528_250))
        XCTAssertTrue(text.contains("Aug"), "Expected en_US month name, got \(text)")
    }
}
