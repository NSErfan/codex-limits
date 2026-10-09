import CodexWidgetKit
import XCTest
@testable import CodexLimits

final class MenuBarUsageWindowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOptionsMatchProviderAccountWindows() {
        XCTAssertEqual(MenuBarUsageWindow.options(for: .codex), [.automatic, .fiveHour, .weekly])
        XCTAssertEqual(MenuBarUsageWindow.options(for: .claude), [.automatic, .fiveHour, .weekly])
        XCTAssertEqual(MenuBarUsageWindow.options(for: .copilot), [.automatic])
    }

    func testAutomaticKeepsLowestRemainingWhileFixedModesSelectEitherAccountWindow() {
        for provider in [UsageProvider.codex, .claude] {
            for percentages in [(20.0, 80.0), (80.0, 20.0), (50.0, 50.0)] {
                let fiveHour = reading(provider, period: .fiveHour, remaining: percentages.0)
                let weekly = reading(provider, period: .weekly, remaining: percentages.1)
                let primary = percentages.0 <= percentages.1 ? fiveHour : weekly
                let snapshot = snapshot(main: primary, others: primary == fiveHour ? [weekly] : [fiveHour])
                XCTAssertEqual(MenuBarUsageWindow.automatic.limit(in: snapshot, provider: provider), primary)
                XCTAssertEqual(MenuBarUsageWindow.fiveHour.limit(in: snapshot, provider: provider), fiveHour)
                XCTAssertEqual(MenuBarUsageWindow.weekly.limit(in: snapshot, provider: provider), weekly)
            }
        }
    }

    func testMissingFixedWindowNeverSubstitutesAnotherAccountOrModelLimit() {
        for provider in [UsageProvider.codex, .claude] {
            let otherProvider: UsageProvider = provider == .codex ? .claude : .codex
            let fiveHour = reading(provider, period: .fiveHour, remaining: 75)
            let weekly = reading(provider, period: .weekly, remaining: 25)
            let model = LimitReading(limitId: "\(provider.rawValue)-model", name: "Model weekly", window: weekly.window)
            let snapshot = snapshot(main: fiveHour, others: [model, reading(otherProvider, period: .weekly, remaining: 1)])
            XCTAssertNil(MenuBarUsageWindow.weekly.limit(in: snapshot, provider: provider))
            XCTAssertEqual(MenuBarUsageWindow.fiveHour.limit(in: snapshot, provider: provider), fiveHour)
            XCTAssertNil(MenuBarUsageWindow.fiveHour.limit(in: self.snapshot(main: weekly), provider: provider))
            for selection in MenuBarUsageWindow.allCases {
                XCTAssertNil(selection.limit(in: nil, provider: provider))
            }
        }
    }

    func testFixedWindowsRejectUnknownDurationsAndInvalidReadings() {
        for provider in [UsageProvider.codex, .claude] {
            for selection in [MenuBarUsageWindow.fiveHour, .weekly] {
                let period: UsagePeriod = selection == .fiveHour ? .fiveHour : .weekly
                for remaining in [Double.nan, .infinity, -.infinity, -1, 101] {
                    let invalid = reading(provider, period: period, remaining: remaining)
                    XCTAssertNil(selection.limit(in: snapshot(main: invalid), provider: provider))
                }
                let expired = reading(provider, period: period, remaining: 40, reset: now.addingTimeInterval(-1))
                XCTAssertNil(selection.limit(in: snapshot(main: expired), provider: provider))
                let unknown = LimitReading(limitId: provider.rawValue, name: "Unknown", window: UsageWindow(
                    remainingPercent: 40, resetsAt: now.addingTimeInterval(3_600), durationMinutes: period.durationMinutes + 1
                ))
                XCTAssertNil(selection.limit(in: snapshot(main: unknown), provider: provider))
            }
        }
    }

    func testFixedWindowsIncludeZeroFullAllowanceAndExactResetBoundary() {
        for provider in [UsageProvider.codex, .claude] {
            for remaining in [0.0, 100.0] {
                for selection in [MenuBarUsageWindow.fiveHour, .weekly] {
                    let period: UsagePeriod = selection == .fiveHour ? .fiveHour : .weekly
                    let limit = reading(provider, period: period, remaining: remaining, reset: now)
                    XCTAssertEqual(selection.limit(in: snapshot(main: limit), provider: provider), limit)
                }
            }
        }
    }

    func testCopilotKeepsMonthlyAllowanceForEverySuppliedSelection() {
        let monthly = reading(.copilot, period: .monthly, remaining: 46)
        for selection in MenuBarUsageWindow.allCases {
            XCTAssertEqual(selection.limit(in: snapshot(main: monthly), provider: .copilot), monthly)
        }
    }

    func testClaudeParsedWindowsSupportFixedFiveHourWhenWeeklyIsLower() throws {
        let report = try ClaudeUsageFixture.output(limits: [
            ClaudeUsageFixture.limit("session", percent: 10),
            ClaudeUsageFixture.limit(percent: 80)
        ])
        let parsed = try ClaudeClient.decode(report, fetchedAt: now)
        XCTAssertEqual(MenuBarUsageWindow.automatic.limit(in: parsed, provider: .claude)?.window.remainingPercent, 20)
        XCTAssertEqual(MenuBarUsageWindow.fiveHour.limit(in: parsed, provider: .claude)?.window.remainingPercent, 90)
        XCTAssertEqual(MenuBarUsageWindow.weekly.limit(in: parsed, provider: .claude)?.window.remainingPercent, 20)
    }

    private func reading(_ provider: UsageProvider, period: UsagePeriod, remaining: Double, reset: Date? = nil) -> LimitReading {
        LimitReading(limitId: provider.rawValue, name: period.title, window: UsageWindow(
            remainingPercent: remaining, resetsAt: reset ?? now.addingTimeInterval(3_600), durationMinutes: period.durationMinutes
        ))
    }

    private func snapshot(main: LimitReading, others: [LimitReading] = []) -> UsageSnapshot {
        UsageSnapshot(mainLimit: main, otherLimits: others, tokenHistory: [], resetCredits: [], fetchedAt: now)
    }
}
