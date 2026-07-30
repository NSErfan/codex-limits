import XCTest
@testable import CodexLimits

final class UsageMonitorHelpersTests: XCTestCase {
    func testMenuBarTextRoundsAndHandlesMissingSnapshot() {
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: nil), "—")
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: 45.6), "46%")
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: 0), "0%")
    }

    func testWindowSamplesKeepOnlyTheCurrentResetSortedByTime() {
        let reset = Date(timeIntervalSince1970: 2_000_000)
        let otherReset = Date(timeIntervalSince1970: 3_000_000)
        let samples = [
            UsageSample(observedAt: Date(timeIntervalSince1970: 1_200), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: Date(timeIntervalSince1970: 600), remainingPercent: 90, resetsAt: reset),
            UsageSample(observedAt: Date(timeIntervalSince1970: 900), remainingPercent: 85, resetsAt: otherReset)
        ]

        let filtered = UsageMonitor.windowSamples(samples, reset: reset)

        XCTAssertEqual(filtered.map(\.remainingPercent), [90, 80])
        XCTAssertEqual(UsageMonitor.windowSamples(samples, reset: nil), [])
    }
}
