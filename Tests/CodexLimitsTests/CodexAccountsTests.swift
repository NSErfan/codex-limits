//
//  CodexAccountsTests.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class CodexAccountsTests: XCTestCase {
    func testBothAccountsKeepSeparateReadingsAndHistoryWithoutChangingThePrimaryWidget() async throws {
        let suite = "CodexAccountsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        defaults.set(true, forKey: UsageAccount.secondCodexEnabledKey)
        defaults.set(["claude", "copilot"], forKey: ProviderEnablement.disabledKey)
        let store = WeeklyWidgetStore(directory: directory.appendingPathComponent("widget"))
        let sharedHistory = directory.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: sharedHistory, withIntermediateDirectories: true)
        let now = Date()
        let primaryReading = Self.snapshot(at: now, remaining: 85, email: "first@example.test")
        let secondaryReading = Self.snapshot(at: now, remaining: 19, email: "second@example.test")
        func historyDirectory(for account: UsageAccount) -> URL {
            directory.appendingPathComponent(account.localHistoryDirectoryName, isDirectory: true)
        }
        func monitor(_ account: UsageAccount, reading: UsageSnapshot) -> UsageMonitor {
            UsageMonitor(account: account, defaults: defaults, historyDirectory: historyDirectory(for: account),
                         widgetStore: store, fetchUsage: { reading }, startsAutomatically: false)
        }
        let primary = monitor(.primaryCodex, reading: primaryReading)
        let secondary = monitor(.secondaryCodex, reading: secondaryReading)
        let providers = UsageProviders(defaults: defaults, codex: primary, secondCodex: secondary, widgetStore: nil)

        await primary.connectHistoryFolder(sharedHistory)
        await secondary.connectHistoryFolder(sharedHistory)
        await providers.refreshAll()
        XCTAssertEqual(primary.snapshot, primaryReading)
        XCTAssertEqual(secondary.snapshot, secondaryReading)
        XCTAssertEqual(primary.samples(for: .weekly).map(\.remainingPercent), [85])
        XCTAssertEqual(secondary.samples(for: .weekly).map(\.remainingPercent), [19])
        XCTAssertNil(primary.syncErrorMessage)
        XCTAssertNil(secondary.syncErrorMessage)
        let sharedFiles = try XCTUnwrap(FileManager.default.enumerator(atPath: sharedHistory.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }
        XCTAssertTrue(sharedFiles.contains { $0.hasPrefix("Windows/10080/") })
        XCTAssertTrue(sharedFiles.contains { $0.hasPrefix("Codex 2/Windows/10080/") })
        XCTAssertEqual(store.read()?.window?.remainingPercent, 85)

        let collected = await BackgroundCollector.collectOnce(
            defaults: defaults, historyDirectory: historyDirectory(for: .secondaryCodex), widgetStore: store,
            account: .secondaryCodex, fetchUsage: { secondaryReading }
        )
        XCTAssertTrue(collected)
        XCTAssertEqual(store.read()?.window?.remainingPercent, 85)

        let reloadedPrimary = monitor(.primaryCodex, reading: primaryReading)
        let reloadedSecondary = monitor(.secondaryCodex, reading: secondaryReading)
        XCTAssertEqual(reloadedPrimary.snapshot, primaryReading)
        XCTAssertEqual(reloadedSecondary.snapshot, secondaryReading)
        XCTAssertTrue(providers.selectAccount(.secondaryCodex))
        let relaunched = UsageProviders(defaults: defaults, codex: reloadedPrimary, secondCodex: reloadedSecondary, widgetStore: nil)
        XCTAssertTrue(relaunched.selectedMonitor === reloadedSecondary)

        providers.setSecondCodexEnabled(false)
        XCTAssertTrue(providers.selectedMonitor === primary)
        let refreshedWhileOff = await secondary.refresh()
        XCTAssertFalse(refreshedWhileOff)
        XCTAssertEqual(secondary.snapshot, secondaryReading)
    }

    func testPrimaryHomeAliasCannotBeUsedByTheSecondAccount() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let home = directory.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let alias = directory.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: home)

        XCTAssertThrowsError(try CodexProfile.prepareSecondaryHome(home, environment: ["CODEX_HOME": alias.path])) {
            guard case CodexClientError.profileAlreadyInUse = $0 else {
                return XCTFail("Expected the accounts to reject a shared profile")
            }
        }
    }

    private static func snapshot(at now: Date, remaining: Double, email: String) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(limitId: "codex", name: "Codex", window: UsageWindow(
                remainingPercent: remaining, resetsAt: now.addingTimeInterval(3600), durationMinutes: 10_080
            )),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: now, accountName: email
        )
    }
}
