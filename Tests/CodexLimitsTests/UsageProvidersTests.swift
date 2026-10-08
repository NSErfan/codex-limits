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
        let providers = context.providers(codex: codex, claude: claude)

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
        let providers = context.providers(codex: codex, claude: claude)
        XCTAssertEqual(providers.selectedProvider, .codex)
        XCTAssertTrue(providers.selectedMonitor === codex)

        providers.selectedProvider = .claude
        let relaunched = context.providers(codex: codex, claude: claude)

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

        let providers = context.providers(codex: codex, claude: claude)

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
        await context.providers(codex: codex, claude: claude).refreshAll()
        let codexWidget = context.widgetStore(for: .codex).read()
        let claudeWidget = context.widgetStore(for: .claude).read()
        let failingCodex = context.monitor(for: .codex) { throw FetchFailure.generic }
        let failingClaude = context.monitor(for: .claude) { throw FetchFailure.loginRequired }

        await context.providers(codex: failingCodex, claude: failingClaude).refreshAll()

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

    func testSharedHistoryFolderKeepsProvidersSeparateInEveryConnectionOrder() async throws {
        let providers = UsageProvider.allCases
        let remaining: [UsageProvider: Double] = [.codex: 81, .claude: 39, .copilot: 57]
        for offset in providers.indices {
            let order = Array(providers[offset...] + providers[..<offset])
            let context = try makeContext()
            defer { context.cleanUp() }
            let shared = context.directory.appendingPathComponent("shared", isDirectory: true)
            try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
            func monitor(for provider: UsageProvider, in context: Context) -> UsageMonitor {
                let snapshot = Self.snapshot(provider: provider, remainingPercent: remaining[provider]!)
                return context.monitor(for: provider) { snapshot }
            }
            let monitors = Dictionary(uniqueKeysWithValues: providers.map { ($0, monitor(for: $0, in: context)) })
            let usageProviders = context.providers(
                codex: monitors[.codex]!, claude: monitors[.claude]!, copilot: monitors[.copilot]!
            )
            await usageProviders.refreshAll()

            for provider in order {
                await usageProviders.monitor(for: provider).connectHistoryFolder(shared)
            }
            await usageProviders.refreshAll()

            for provider in providers {
                let monitor = try XCTUnwrap(monitors[provider])
                XCTAssertNil(monitor.syncErrorMessage, "Order: \(order), provider: \(provider)")
                XCTAssertEqual(monitor.syncFolderName, shared.lastPathComponent)
                XCTAssertEqual(monitor.samples.map(\.remainingPercent), [remaining[provider]!])
                XCTAssertNotNil(context.defaults.data(forKey: provider.preferenceKey("historySyncBookmark")))
            }

            var relaunched: [UsageProvider: UsageMonitor] = [:]
            for provider in providers {
                let monitor = monitor(for: provider, in: context)
                await monitor.refresh()
                XCTAssertNil(monitor.syncErrorMessage, "Order: \(order), provider: \(provider)")
                XCTAssertEqual(monitor.syncFolderName, shared.lastPathComponent)
                XCTAssertEqual(monitor.samples.map(\.remainingPercent), [remaining[provider]!])
                relaunched[provider] = monitor
            }

            let otherInstallation = try makeContext()
            defer { otherInstallation.cleanUp() }
            for provider in providers {
                let other = otherInstallation.monitor(for: provider) { throw FetchFailure.generic }
                await other.connectHistoryFolder(shared)
                XCTAssertNil(other.syncErrorMessage, "Order: \(order), provider: \(provider)")
                XCTAssertEqual(other.samples.map(\.remainingPercent), [remaining[provider]!])
            }

            await relaunched[.claude]?.stopHistorySync()
            XCTAssertNil(context.defaults.data(forKey: "claude.historySyncBookmark"))
            XCTAssertNotNil(context.defaults.data(forKey: "historySyncBookmark"))
            XCTAssertNotNil(context.defaults.data(forKey: "copilot.historySyncBookmark"))
            XCTAssertNil(relaunched[.claude]?.syncFolderName)
            XCTAssertEqual(relaunched[.codex]?.syncFolderName, shared.lastPathComponent)
            XCTAssertEqual(relaunched[.copilot]?.syncFolderName, shared.lastPathComponent)
        }
    }

    func testPaceTargetsRemainSeparateWhileSafetyBufferUpdatesBothProviders() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let codexSnapshot = Self.snapshot(provider: .codex, remainingPercent: 59)
        let claudeSnapshot = Self.snapshot(provider: .claude, remainingPercent: 59)
        let codex = context.monitor(for: .codex) { codexSnapshot }
        let claude = context.monitor(for: .claude) { claudeSnapshot }
        let providers = context.providers(codex: codex, claude: claude)
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
                    durationMinutes: provider.periods.last!.durationMinutes
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

        func providers(
            codex: UsageMonitor,
            claude: UsageMonitor,
            copilot: UsageMonitor? = nil
        ) -> UsageProviders {
            UsageProviders(
                defaults: defaults, codex: codex, claude: claude,
                copilot: copilot ?? monitor(for: .copilot) { throw FetchFailure.loginRequired }
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
