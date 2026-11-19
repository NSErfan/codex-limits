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
        let secondaryReading = Self.snapshot(at: now, remaining: 19, email: "second@example.test", workspace: "second-workspace")
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
        await providers.refreshAll()
        await secondary.connectHistoryFolder(sharedHistory)
        XCTAssertEqual(primary.snapshot, primaryReading)
        XCTAssertEqual(secondary.snapshot, secondaryReading)
        XCTAssertEqual(primary.samples(for: .weekly).map(\.remainingPercent), [85])
        XCTAssertEqual(secondary.samples(for: .weekly).map(\.remainingPercent), [19])
        XCTAssertNil(primary.syncErrorMessage)
        XCTAssertNil(secondary.syncErrorMessage)
        let sharedFiles = try XCTUnwrap(FileManager.default.enumerator(atPath: sharedHistory.path))
            .compactMap { $0 as? String }.filter { $0.hasSuffix(".json") }
        XCTAssertTrue(sharedFiles.contains { $0.hasPrefix("Windows/10080/") })
        let secondaryKey = try XCTUnwrap(secondaryReading.subscriptionKey)
        XCTAssertTrue(sharedFiles.contains { $0.hasPrefix("Codex 2/Subscriptions/\(secondaryKey.rawValue)/Windows/10080/") })
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

    func testAccountOrderSurvivesRelaunchAndKeepsHiddenAccountsInPlace() throws {
        let suite = "CodexAccountsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: UsageAccount.secondCodexEnabledKey)
        defaults.set(["unknown", "codex", "codex"], forKey: UsageProviders.accountOrderKey)

        func makeProviders() -> UsageProviders {
            func monitor(_ account: UsageAccount) -> UsageMonitor {
                let path = directory.appendingPathComponent(account.rawValue, isDirectory: true)
                return UsageMonitor(account: account, defaults: defaults, historyDirectory: path,
                    widgetStore: WeeklyWidgetStore(directory: path, provider: account.provider),
                    startsAutomatically: false)
            }
            return UsageProviders(defaults: defaults, codex: monitor(.primaryCodex), secondCodex: monitor(.secondaryCodex),
                                  claude: monitor(.claude), copilot: monitor(.copilot), widgetStore: nil)
        }

        let providers = makeProviders()
        XCTAssertEqual(providers.enabledAccounts, [.primaryCodex, .secondaryCodex, .claude, .copilot])
        XCTAssertTrue(providers.selectAccount(.copilot))
        let selected = providers.selectedMonitor

        providers.moveAccount(.secondaryCodex, .earlier)
        providers.moveAccount(.secondaryCodex, .earlier)
        providers.moveAccount(.copilot, .earlier)
        XCTAssertEqual(providers.enabledAccounts, [.secondaryCodex, .primaryCodex, .copilot, .claude])
        XCTAssertTrue(providers.selectedMonitor === selected)
        XCTAssertEqual(makeProviders().enabledAccounts, providers.enabledAccounts)

        providers.setSecondCodexEnabled(false)
        providers.moveAccount(.copilot, .earlier)
        XCTAssertEqual(providers.enabledAccounts, [.copilot, .primaryCodex, .claude])
        providers.setSecondCodexEnabled(true)
        XCTAssertEqual(providers.enabledAccounts, [.secondaryCodex, .copilot, .primaryCodex, .claude])
        providers.setSecondCodexEnabled(false)
    }

    func testWorkspaceSwitchSeparatesCollectorHistoryAndSyncEvenWhenEmailMatches() async throws {
        let suite = "CodexAccountsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let local = directory.appendingPathComponent("local")
        let sync = directory.appendingPathComponent("sync")
        try FileManager.default.createDirectory(at: sync, withIntermediateDirectories: true)
        let now = Date().addingTimeInterval(-600)
        let email = "same@example.test"
        let first = Self.snapshot(at: now, remaining: 80, email: email, workspace: "first")
        let collector = Self.snapshot(at: now + 60, remaining: 42, email: email, workspace: "second")
        let second = Self.snapshot(at: now + 120, remaining: 39, email: email, workspace: "second")
        let unknown = Self.snapshot(at: now + 180, remaining: 12, email: email)
        let returnToFirst = Self.snapshot(at: now + 240, remaining: 78, email: email, workspace: "first")
        let source = SnapshotSequence([first, second, unknown, returnToFirst])
        let monitor = UsageMonitor(account: .secondaryCodex, defaults: defaults, historyDirectory: local,
                                   fetchUsage: { await source.next() }, startsAutomatically: false)
        let legacy = UsageHistory(localDirectory: local, installationID: UUID().uuidString.lowercased())
        let previousSample = try XCTUnwrap(Self.snapshot(at: now - 60, remaining: 97, email: email)
            .sample(for: .weekly, provider: .codex))
        _ = await legacy.record(previousSample)

        await monitor.refresh()
        await monitor.connectHistoryFolder(sync)
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.remainingPercent), [80])
        XCTAssertEqual(monitor.syncFolderName, "sync")

        let collected = await BackgroundCollector.collectOnce(
            defaults: defaults, historyDirectory: local, account: .secondaryCodex, fetchUsage: { collector }
        )
        XCTAssertTrue(collected)
        await monitor.refresh()
        XCTAssertEqual(monitor.snapshot, second)
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.remainingPercent), [42, 39])
        XCTAssertNil(monitor.syncFolderName)
        let secondKey = try XCTUnwrap(second.subscriptionKey)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sync.appendingPathComponent("Codex 2/Subscriptions/\(secondKey.rawValue)").path
        ))

        let recordedUnknown = await BackgroundCollector.collectOnce(
            defaults: defaults, historyDirectory: local, account: .secondaryCodex, fetchUsage: { unknown }
        )
        XCTAssertFalse(recordedUnknown)
        await monitor.refresh()
        XCTAssertEqual(monitor.snapshot, unknown)
        XCTAssertFalse(monitor.allowsHistorySync)
        XCTAssertTrue(monitor.samples.isEmpty)
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.remainingPercent), [12])

        await monitor.refresh()
        XCTAssertEqual(monitor.samples(for: .weekly).map(\.remainingPercent), [80, 78])
        XCTAssertEqual(monitor.syncFolderName, "sync")
        let legacyState = await legacy.synchronize()
        XCTAssertEqual(legacyState.samples.map(\.remainingPercent), [97])
    }

    private actor SnapshotSequence {
        var snapshots: [UsageSnapshot]
        init(_ snapshots: [UsageSnapshot]) { self.snapshots = snapshots }
        func next() -> UsageSnapshot { snapshots.removeFirst() }
    }

    private static func snapshot(at now: Date, remaining: Double, email: String, workspace: String? = nil) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(limitId: "codex", name: "Codex", window: UsageWindow(
                remainingPercent: remaining, resetsAt: now.addingTimeInterval(3600), durationMinutes: 10_080
            )),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: now, accountName: email,
            subscriptionKey: workspace.map { UsageSubscriptionKey(workspaceID: $0, accountName: email) }
        )
    }
}
