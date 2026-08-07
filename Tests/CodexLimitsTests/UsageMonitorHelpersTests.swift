import XCTest
@testable import CodexLimits

final class UsageMonitorHelpersTests: XCTestCase {
    func testMenuBarTextRoundsAndHandlesMissingSnapshot() {
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: nil), "—")
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: 45.6), "46%")
        XCTAssertEqual(UsageMonitor.menuBarText(remainingPercent: 0), "0%")
    }

    func testMergedSamplesNeverShrinkOnPartialIncomingState() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let reset = now.addingTimeInterval(86_400)
        let known = [
            UsageSample(observedAt: now.addingTimeInterval(-7_200), remainingPercent: 80, resetsAt: reset),
            UsageSample(observedAt: now.addingTimeInterval(-3_600), remainingPercent: 75, resetsAt: reset)
        ]
        let partialRead = [known[1]]

        let merged = UsageMonitor.mergedSamples(known, partialRead)

        XCTAssertEqual(merged, known)
        XCTAssertEqual(UsageMonitor.mergedSamples(known, []), known)
    }

    func testMergedSamplesDeduplicateAndEnforceRetention() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let reset = now.addingTimeInterval(86_400)
        let expired = UsageSample(
            observedAt: now.addingTimeInterval(-91 * 86_400),
            remainingPercent: 50,
            resetsAt: now.addingTimeInterval(-90 * 86_400)
        )
        let shared = UsageSample(observedAt: now.addingTimeInterval(-600), remainingPercent: 70, resetsAt: reset)
        let incomingOnly = UsageSample(observedAt: now, remainingPercent: 68, resetsAt: reset)

        let merged = UsageMonitor.mergedSamples([expired, shared], [shared, incomingOnly])

        XCTAssertEqual(merged, [shared, incomingOnly])
    }

    func testPersistedSamplesAreBoundedToThirtyDaysAndCapped() {
        let now = Date(timeIntervalSince1970: 20_000_000)
        let reset = now.addingTimeInterval(86_400)
        let old = UsageSample(
            observedAt: now.addingTimeInterval(-31 * 86_400),
            remainingPercent: 90,
            resetsAt: now.addingTimeInterval(-30 * 86_400)
        )
        let recent = (0 ..< 4_100).map {
            UsageSample(
                observedAt: now.addingTimeInterval(Double($0 - 4_100) * 60),
                remainingPercent: 50,
                resetsAt: reset
            )
        }

        let persisted = UsageMonitor.samplesForPersistence([old] + recent)

        XCTAssertEqual(persisted.count, 4_000)
        XCTAssertEqual(persisted.last, recent.last)
        XCTAssertFalse(persisted.contains(old))
        XCTAssertEqual(persisted.first, recent[100])
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
