import Foundation
import XCTest
@testable import CodexLimits

final class UsageURLHandlerTests: XCTestCase {
    func testWidgetLinksSelectTheirProvider() {
        XCTAssertEqual(UsageURLHandler.provider(from: URL(string: "codexlimits://usage/codex")!), .codex)
        XCTAssertEqual(UsageURLHandler.provider(from: URL(string: "codexlimits://usage/claude")!), .claude)
    }

    func testUnrelatedRoutesDoNotChangeProvider() {
        let invalidLinks = [
            "https://usage/claude", "codexlimits://settings/claude",
            "codexlimits://usage/unknown", "codexlimits://usage/nested/claude",
            "codexlimits://someone@usage/claude", "codexlimits://usage:123/claude",
            "codexlimits://usage"
        ]
        for link in invalidLinks {
            XCTAssertNil(UsageURLHandler.provider(from: URL(string: link)!), link)
        }
    }
}
