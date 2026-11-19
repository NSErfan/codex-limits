import Foundation
import XCTest
@testable import CodexLimits

final class UsageURLHandlerTests: XCTestCase {
    func testWidgetAndLoginLinksSelectTheirAccount() {
        XCTAssertEqual(UsageURLHandler.account(from: URL(string: "codexlimits://usage/codex")!), .primaryCodex)
        XCTAssertEqual(UsageURLHandler.account(from: URL(string: "codexlimits://usage/codex-secondary")!), .secondaryCodex)
        XCTAssertEqual(UsageURLHandler.account(from: URL(string: "codexlimits://usage/claude")!), .claude)
    }

    func testUnrelatedRoutesDoNotChangeProvider() {
        let invalidLinks = [
            "https://usage/claude", "codexlimits://settings/claude",
            "codexlimits://usage/unknown", "codexlimits://usage/nested/claude",
            "codexlimits://someone@usage/claude", "codexlimits://usage:123/claude",
            "codexlimits://usage"
        ]
        for link in invalidLinks {
            XCTAssertNil(UsageURLHandler.account(from: URL(string: link)!), link)
        }
    }
}
