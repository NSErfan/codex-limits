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

        XCTAssertTrue(providers.select(.claude))
        let relaunched = context.providers(codex: codex, claude: claude)

        XCTAssertEqual(context.defaults.string(forKey: UsageProviders.selectionKey), "claude")
        XCTAssertEqual(relaunched.selectedProvider, .claude)
        XCTAssertTrue(relaunched.selectedMonitor === claude)
        XCTAssertTrue(relaunched.monitor(for: .codex) === codex)
        XCTAssertTrue(relaunched.select(.codex))
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

    func testTurningOffSelectedProviderMovesSelectionToFirstProviderThatIsOn() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: context.idleMonitor(for: .claude))
        XCTAssertTrue(providers.select(.claude))

        providers.setEnabled(false, for: .claude)

        XCTAssertEqual(providers.enabledProviders, [.codex, .copilot])
        XCTAssertEqual(providers.selectedProvider, .codex)
        XCTAssertTrue(providers.selectedMonitor === providers.codex)
        XCTAssertEqual(context.defaults.string(forKey: UsageProviders.selectionKey), "codex")
        XCTAssertEqual(context.defaults.stringArray(forKey: ProviderEnablement.disabledKey), ["claude"])
    }

    func testSavedSelectionOfTurnedOffProviderFallsBackOnLaunch() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set("codex", forKey: UsageProviders.selectionKey)
        context.defaults.set(["codex"], forKey: ProviderEnablement.disabledKey)

        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: context.idleMonitor(for: .claude))

        XCTAssertEqual(providers.selectedProvider, .claude)
        XCTAssertEqual(providers.enabledProviders, [.claude, .copilot])
    }

    func testSelectingTurnedOffProviderIsIgnored() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: context.idleMonitor(for: .claude))
        providers.setEnabled(false, for: .copilot)

        XCTAssertFalse(providers.select(.copilot))
        XCTAssertEqual(providers.selectedProvider, .codex)
    }

    func testTurnedOffProvidersAreStoppedAndSkippedByRefreshAll() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(["claude"], forKey: ProviderEnablement.disabledKey)
        let counters = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { ($0, FetchCounter()) })
        func countingMonitor(_ provider: UsageProvider) -> UsageMonitor {
            let counter = counters[provider]!
            let snapshot = Self.snapshot(provider: provider, remainingPercent: 50)
            return context.monitor(for: provider) {
                await counter.record()
                return snapshot
            }
        }
        let providers = context.providers(
            codex: countingMonitor(.codex), claude: countingMonitor(.claude), copilot: countingMonitor(.copilot)
        )

        await providers.refreshAll()
        let manualRefresh = await providers.claude.refresh()

        XCTAssertFalse(manualRefresh, "A turned-off provider is stopped even when injected")
        for (provider, expected) in [(UsageProvider.codex, 1), (.claude, 0), (.copilot, 1)] {
            let count = await counters[provider]!.count
            XCTAssertEqual(count, expected, "\(provider)")
        }
    }

    func testTurningProviderBackOnStartsAndRefreshesIt() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(["claude"], forKey: ProviderEnablement.disabledKey)
        let counter = FetchCounter()
        let snapshot = Self.snapshot(provider: .claude, remainingPercent: 44)
        let claude = context.monitor(for: .claude) {
            await counter.record()
            return snapshot
        }
        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: claude)

        providers.setEnabled(true, for: .claude)
        await counter.waitForCount(1)
        defer { providers.setEnabled(false, for: .claude) }
        for _ in 0 ..< 200 where claude.snapshot == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(providers.isEnabled(.claude))
        XCTAssertEqual(claude.snapshot, snapshot)
        XCTAssertTrue(providers.select(.claude))
    }

    func testQuickOffOnOffLeavesProviderStopped() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let counter = FetchCounter()
        let snapshot = Self.snapshot(provider: .claude, remainingPercent: 44)
        let claude = context.monitor(for: .claude) {
            await counter.record()
            return snapshot
        }
        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: claude)

        providers.setEnabled(false, for: .claude)
        providers.setEnabled(true, for: .claude)
        providers.setEnabled(false, for: .claude)
        try await Task.sleep(for: .milliseconds(100))
        let refused = await claude.refresh()

        XCTAssertFalse(refused)
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testAutoStartingInjectedMonitorForTurnedOffProviderStaysStopped() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(["claude"], forKey: ProviderEnablement.disabledKey)
        let counter = FetchCounter()
        let snapshot = Self.snapshot(provider: .claude, remainingPercent: 44)
        let claude = UsageMonitor(
            provider: .claude, defaults: context.defaults,
            historyDirectory: context.directory.appendingPathComponent("claude", isDirectory: true),
            widgetStore: context.widgetStore(for: .claude),
            fetchUsage: {
                await counter.record()
                return snapshot
            },
            recoveryDelaysNanoseconds: []
        )

        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: claude)
        try await Task.sleep(for: .milliseconds(100))
        let refused = await claude.refresh()

        XCTAssertFalse(providers.isEnabled(.claude))
        XCTAssertFalse(refused)
        let count = await counter.count
        XCTAssertEqual(count, 0)
    }

    func testTurningOffFromStoredStateWithEveryProviderOffHidesThatProvider() async throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(UsageProvider.allCases.map(\.rawValue), forKey: ProviderEnablement.disabledKey)
        let snapshot = Self.snapshot(provider: .codex, remainingPercent: 52)
        let codex = context.monitor(for: .codex) { snapshot }
        let providers = context.providers(codex: codex, claude: context.idleMonitor(for: .claude))
        XCTAssertEqual(providers.enabledProviders, UsageProvider.allCases)

        providers.setEnabled(false, for: .claude)

        XCTAssertEqual(providers.enabledProviders, [.codex, .copilot])
        let refreshedCodex = await codex.refresh()
        XCTAssertTrue(refreshedCodex)
        let refreshedClaude = await providers.claude.refresh()
        XCTAssertFalse(refreshedClaude)
    }

    func testLastProviderThatIsOnStaysOn() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        let providers = context.providers(codex: context.idleMonitor(for: .codex), claude: context.idleMonitor(for: .claude))
        providers.setEnabled(false, for: .claude)
        providers.setEnabled(false, for: .copilot)

        providers.setEnabled(false, for: .codex)

        XCTAssertEqual(providers.enabledProviders, [.codex])
        XCTAssertEqual(providers.selectedProvider, .codex)
        XCTAssertEqual(Set(context.defaults.stringArray(forKey: ProviderEnablement.disabledKey) ?? []), ["claude", "copilot"])
    }

    func testTurnedOffProvidersAreSharedWithWidgets() throws {
        let context = try makeContext()
        defer { context.cleanUp() }
        context.defaults.set(["copilot"], forKey: ProviderEnablement.disabledKey)
        let store = context.widgetStore(for: .codex)
        var reloads = 0
        func makeProviders() -> UsageProviders {
            UsageProviders(defaults: context.defaults, codex: context.idleMonitor(for: .codex),
                           claude: context.idleMonitor(for: .claude), copilot: context.idleMonitor(for: .copilot),
                           widgetStore: store, reloadWidgets: { reloads += 1 })
        }

        let providers = makeProviders()
        XCTAssertEqual(store.readDisabledProviders(), [.copilot], "Launch repairs missing widget data")
        XCTAssertEqual(reloads, 1)

        providers.setEnabled(false, for: .claude)
        XCTAssertEqual(store.readDisabledProviders(), [.claude, .copilot])
        XCTAssertEqual(reloads, 2)

        _ = makeProviders()
        XCTAssertEqual(reloads, 2, "Launch doesn't rewrite matching widget data")
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

        func idleMonitor(for provider: UsageProvider) -> UsageMonitor {
            monitor(for: provider) { throw FetchFailure.generic }
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

    private actor FetchCounter {
        private(set) var count = 0
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

        func record() {
            count += 1
            let ready = waiters.filter { count >= $0.0 }
            waiters.removeAll { count >= $0.0 }
            ready.forEach { $0.1.resume() }
        }

        func waitForCount(_ expected: Int) async {
            guard count < expected else { return }
            await withCheckedContinuation { waiters.append((expected, $0)) }
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
