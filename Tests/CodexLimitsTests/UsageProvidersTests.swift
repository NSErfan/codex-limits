import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class UsageProvidersTests: XCTestCase {
    func testSnapshotsAndHistoryRemainSeparateAfterRelaunch() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let codexSnapshot = Self.snapshot(provider: .codex, remainingPercent: 81)
        let claudeSnapshot = Self.snapshot(provider: .claude, remainingPercent: 39)
        let codex = context.monitor(for: .codex) { codexSnapshot }
        let claude = context.monitor(for: .claude) { claudeSnapshot }
        let providers = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)

        await providers.refreshAll()

        XCTAssertEqual(codex.snapshot, codexSnapshot)
        XCTAssertEqual(claude.snapshot, claudeSnapshot)
        XCTAssertEqual(codex.samples.map(\.remainingPercent), [81])
        XCTAssertEqual(claude.samples.map(\.remainingPercent), [39])
        XCTAssertNotNil(context.defaults.data(forKey: "usageState"))
        XCTAssertNotNil(context.defaults.data(forKey: "claude.usageState"))

        let relaunchedCodex = context.monitor(for: .codex) { codexSnapshot }
        let relaunchedClaude = context.monitor(for: .claude) { claudeSnapshot }
        XCTAssertEqual(relaunchedCodex.snapshot, codexSnapshot)
        XCTAssertEqual(relaunchedClaude.snapshot, claudeSnapshot)
        XCTAssertEqual(relaunchedCodex.samples, codex.samples)
        XCTAssertEqual(relaunchedClaude.samples, claude.samples)

        await relaunchedCodex.refresh()
        await relaunchedClaude.refresh()

        XCTAssertEqual(relaunchedCodex.samples, codex.samples)
        XCTAssertEqual(relaunchedClaude.samples, claude.samples)
        XCTAssertEqual(context.widgetStore(for: .codex).read()?.window?.remainingPercent, 81)
        XCTAssertEqual(context.widgetStore(for: .claude).read()?.window?.remainingPercent, 39)
    }

    func testClaudeDoesNotRestoreLegacyCodexState() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let snapshot = Self.snapshot(provider: .codex, remainingPercent: 81)
        let codex = context.monitor(for: .codex) { snapshot }
        await codex.refresh()

        let claude = context.monitor(for: .claude) { throw FetchFailure.loginRequired }

        XCTAssertNil(claude.snapshot)
        XCTAssertTrue(claude.samples.isEmpty)
        XCTAssertNil(claude.forecast)

        await claude.refresh()

        XCTAssertNil(claude.snapshot)
        XCTAssertTrue(claude.samples.isEmpty)
        XCTAssertTrue(claude.requiresLogin)
        XCTAssertEqual(codex.snapshot, snapshot)
        XCTAssertFalse(codex.requiresLogin)
    }

    func testSelectedProviderIsRestoredWithoutChangingMonitorIdentity() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let codex = context.monitor(for: .codex) { throw FetchFailure.generic }
        let claude = context.monitor(for: .claude) { throw FetchFailure.generic }
        let providers = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)
        XCTAssertEqual(providers.selectedProvider, .codex)
        XCTAssertTrue(providers.selectedMonitor === codex)

        providers.selectedProvider = .claude
        let relaunched = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)

        XCTAssertEqual(context.defaults.string(forKey: UsageProviders.selectionKey), "claude")
        XCTAssertEqual(relaunched.selectedProvider, .claude)
        XCTAssertTrue(relaunched.selectedMonitor === claude)
        XCTAssertTrue(relaunched.monitor(for: .codex) === codex)
        relaunched.selectedProvider = .codex
        XCTAssertTrue(relaunched.selectedMonitor === codex)
    }

    func testUnknownSavedProviderFallsBackToCodex() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set("unrecognized", forKey: UsageProviders.selectionKey)
        let codex = context.monitor(for: .codex) { throw FetchFailure.generic }
        let claude = context.monitor(for: .claude) { throw FetchFailure.generic }

        let providers = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)

        XCTAssertEqual(providers.selectedProvider, .codex)
        XCTAssertTrue(providers.selectedMonitor === codex)
    }

    func testProviderFailuresPreserveTheirOwnSnapshotAndWidget() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let codexSnapshot = Self.snapshot(provider: .codex, remainingPercent: 81)
        let claudeSnapshot = Self.snapshot(provider: .claude, remainingPercent: 39)
        let codex = context.monitor(for: .codex) { codexSnapshot }
        let claude = context.monitor(for: .claude) { claudeSnapshot }
        await UsageProviders(defaults: context.defaults, codex: codex, claude: claude).refreshAll()
        let codexWidget = context.widgetStore(for: .codex).read()
        let claudeWidget = context.widgetStore(for: .claude).read()
        let failingCodex = context.monitor(for: .codex) { throw FetchFailure.generic }
        let failingClaude = context.monitor(for: .claude) { throw FetchFailure.loginRequired }

        await UsageProviders(
            defaults: context.defaults, codex: failingCodex, claude: failingClaude
        ).refreshAll()

        XCTAssertEqual(failingCodex.snapshot, codexSnapshot)
        XCTAssertEqual(failingClaude.snapshot, claudeSnapshot)
        XCTAssertEqual(failingCodex.samples, codex.samples)
        XCTAssertEqual(failingClaude.samples, claude.samples)
        XCTAssertFalse(failingCodex.requiresLogin)
        XCTAssertTrue(failingClaude.requiresLogin)
        XCTAssertEqual(failingCodex.errorMessage, FetchFailure.generic.localizedDescription)
        XCTAssertEqual(failingClaude.errorMessage, FetchFailure.loginRequired.localizedDescription)
        XCTAssertEqual(context.widgetStore(for: .codex).read(), codexWidget)
        XCTAssertEqual(context.widgetStore(for: .claude).read(), claudeWidget)

        let recoveredClaude = context.monitor(for: .claude) { claudeSnapshot }
        await recoveredClaude.refresh()
        XCTAssertFalse(recoveredClaude.requiresLogin)
        XCTAssertNil(recoveredClaude.errorMessage)
        XCTAssertEqual(failingCodex.errorMessage, FetchFailure.generic.localizedDescription)
    }

    func testSharedHistoryFolderKeepsProvidersSeparateInEitherConnectionOrder() async throws {
        for firstProvider in UsageProvider.allCases {
            let context = try makeContext()
            defer { context.cleanUp() }
            let shared = context.directory.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            let codexSnapshot = Self.snapshot(provider: .codex, remainingPercent: 81)
            let claudeSnapshot = Self.snapshot(provider: .claude, remainingPercent: 39)
            let codex = context.monitor(for: .codex) { codexSnapshot }
            let claude = context.monitor(for: .claude) { claudeSnapshot }
            let providers = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)
            await providers.refreshAll()
            let secondProvider: UsageProvider = firstProvider == .codex ? .claude : .codex

            await providers.monitor(for: firstProvider).connectHistoryFolder(shared)
            await providers.monitor(for: secondProvider).connectHistoryFolder(shared)
            await providers.refreshAll()

            XCTAssertNil(codex.syncErrorMessage, "First provider: \(firstProvider)")
            XCTAssertNil(claude.syncErrorMessage, "First provider: \(firstProvider)")
            XCTAssertEqual(codex.syncFolderName, shared.lastPathComponent)
            XCTAssertEqual(claude.syncFolderName, shared.lastPathComponent)
            XCTAssertEqual(codex.samples.map(\.remainingPercent), [81])
            XCTAssertEqual(claude.samples.map(\.remainingPercent), [39])
            XCTAssertNotNil(context.defaults.data(forKey: "historySyncBookmark"))
            XCTAssertNotNil(context.defaults.data(forKey: "claude.historySyncBookmark"))

            let relaunchedCodex = context.monitor(for: .codex) { codexSnapshot }
            let relaunchedClaude = context.monitor(for: .claude) { claudeSnapshot }
            await relaunchedCodex.refresh()
            await relaunchedClaude.refresh()

            XCTAssertNil(relaunchedCodex.syncErrorMessage)
            XCTAssertNil(relaunchedClaude.syncErrorMessage)
            XCTAssertEqual(relaunchedCodex.syncFolderName, shared.lastPathComponent)
            XCTAssertEqual(relaunchedClaude.syncFolderName, shared.lastPathComponent)
            XCTAssertEqual(relaunchedCodex.samples.map(\.remainingPercent), [81])
            XCTAssertEqual(relaunchedClaude.samples.map(\.remainingPercent), [39])

            let otherInstallation = try makeContext()
            defer { otherInstallation.cleanUp() }
            let otherCodex = otherInstallation.monitor(for: .codex) { throw FetchFailure.generic }
            let otherClaude = otherInstallation.monitor(for: .claude) { throw FetchFailure.generic }
            await otherCodex.connectHistoryFolder(shared)
            await otherClaude.connectHistoryFolder(shared)

            XCTAssertNil(otherCodex.syncErrorMessage)
            XCTAssertNil(otherClaude.syncErrorMessage)
            XCTAssertEqual(otherCodex.samples.map(\.remainingPercent), [81])
            XCTAssertEqual(otherClaude.samples.map(\.remainingPercent), [39])

            await relaunchedClaude.stopHistorySync()
            XCTAssertNil(context.defaults.data(forKey: "claude.historySyncBookmark"))
            XCTAssertNotNil(context.defaults.data(forKey: "historySyncBookmark"))
            XCTAssertNil(relaunchedClaude.syncFolderName)
            XCTAssertEqual(relaunchedCodex.syncFolderName, shared.lastPathComponent)
        }
    }

    func testPaceTargetsRemainSeparateWhileSafetyBufferUpdatesBothProviders() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let codexSnapshot = Self.snapshot(provider: .codex, remainingPercent: 59)
        let claudeSnapshot = Self.snapshot(provider: .claude, remainingPercent: 59)
        let codex = context.monitor(for: .codex) { codexSnapshot }
        let claude = context.monitor(for: .claude) { claudeSnapshot }
        let providers = UsageProviders(defaults: context.defaults, codex: codex, claude: claude)
        await providers.refreshAll()
        XCTAssertEqual(context.widgetStore(for: .codex).read()?.pace, .onTrack)
        XCTAssertEqual(context.widgetStore(for: .claude).read()?.pace, .onTrack)

        codex.updatePaceTarget("codex-credit")
        claude.updatePaceTarget("claude-credit")
        providers.updateSafetyBuffer(20)

        XCTAssertEqual(context.defaults.string(forKey: "paceTargetCreditID"), "codex-credit")
        XCTAssertEqual(context.defaults.string(forKey: "claude.paceTargetCreditID"), "claude-credit")
        XCTAssertEqual(context.defaults.double(forKey: UsageMonitor.safetyBufferKey), 20)
        XCTAssertEqual(context.widgetStore(for: .codex).read()?.pace, .slowDown)
        XCTAssertEqual(context.widgetStore(for: .claude).read()?.pace, .slowDown)
        XCTAssertEqual(codex.forecast?.status, claude.forecast?.status)
    }

    private func makeContext() throws -> Context {
        let suiteName = "UsageProvidersTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(suiteName, isDirectory: true)
        return Context(defaults: defaults, suiteName: suiteName, directory: directory)
    }

    private static func snapshot(provider: UsageProvider, remainingPercent: Double) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: LimitReading(
                limitId: provider.rawValue,
                name: provider.displayName,
                window: UsageWindow(
                    remainingPercent: remainingPercent,
                    resetsAt: fixtureNow.addingTimeInterval(4 * 86_400),
                    durationMinutes: 7 * 24 * 60
                )
            ),
            otherLimits: [],
            tokenHistory: [],
            resetCredits: [],
            fetchedAt: fixtureNow
        )
    }

    private nonisolated static let fixtureNow = Date(timeIntervalSince1970: 1_900_000)

    @MainActor
    private struct Context {
        let defaults: UserDefaults
        let suiteName: String
        let directory: URL

        func monitor(
            for provider: UsageProvider,
            fetchUsage: @escaping @Sendable () async throws -> UsageSnapshot
        ) -> UsageMonitor {
            UsageMonitor(
                provider: provider,
                defaults: defaults,
                historyDirectory: directory.appendingPathComponent(provider.rawValue, isDirectory: true),
                historyNow: { UsageProvidersTests.fixtureNow },
                widgetStore: widgetStore(for: provider),
                fetchUsage: fetchUsage,
                recoveryDelaysNanoseconds: [],
                startsAutomatically: false
            )
        }

        func widgetStore(for provider: UsageProvider) -> WeeklyWidgetStore {
            WeeklyWidgetStore(
                directory: directory.appendingPathComponent("widget", isDirectory: true),
                provider: provider
            )
        }

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private enum FetchFailure: UsageFetchError {
        case loginRequired
        case generic

        var errorDescription: String? {
            switch self {
            case .loginRequired: "Sign in to continue."
            case .generic: "Usage is unavailable."
            }
        }

        var shouldRetryAutomatically: Bool { false }
        var requiresLogin: Bool { self == .loginRequired }
    }
}
