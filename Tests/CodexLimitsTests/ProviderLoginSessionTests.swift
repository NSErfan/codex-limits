import CodexWidgetKit
import Foundation
import XCTest
@testable import CodexLimits

@MainActor
final class ProviderLoginSessionTests: XCTestCase {
    func testRefreshDoesNotPermitCredentialPromptByDefault() async throws {
        let source = ResultSource([.fetched(Self.snapshot(at: Self.startedAt))])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in })

        await login.refresh(.claude)

        let promptPermissions = await source.promptPermissions
        XCTAssertEqual(promptPermissions, [false])
    }

    func testExplicitRefreshCanPermitCredentialPrompt() async throws {
        let source = ResultSource([.fetched(Self.snapshot(at: Self.startedAt))])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in })

        await login.refresh(.claude, allowCredentialPrompt: true)

        let promptPermissions = await source.promptPermissions
        XCTAssertEqual(promptPermissions, [true])
    }

    func testPendingLoginRetriesDoNotPermitCredentialPromptsAfterAccessDenied() async throws {
        let source = ResultSource([.deferred(ClaudeClientError.keychainAccessDenied, snapshot: nil)])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in }, now: { Self.startedAt })
        await openLogin(login)

        await login.refreshPendingLogins()
        await login.refreshPendingLogins()

        let promptPermissions = await source.promptPermissions
        XCTAssertEqual(promptPermissions, [false, false])
        XCTAssertNotNil(login.message(for: .claude))
        XCTAssertEqual(context.providers.claude.errorMessage, ClaudeClientError.keychainAccessDenied.localizedDescription)
        XCTAssertFalse(context.providers.claude.requiresLogin)
    }

    func testDeniedPassiveRefreshPreservesUsageUntilExplicitRecovery() async throws {
        let savedSnapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(-60))
        let recoveredSnapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(60))
        let source = ResultSource([
            .fetched(savedSnapshot),
            .deferred(ClaudeClientError.keychainAccessDenied, snapshot: nil),
            .fetched(recoveredSnapshot)
        ])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in })
        await login.refresh(.claude)

        await login.refresh(.claude)

        XCTAssertEqual(context.providers.claude.snapshot, savedSnapshot)
        XCTAssertEqual(context.providers.claude.errorMessage, ClaudeClientError.keychainAccessDenied.localizedDescription)
        XCTAssertFalse(context.providers.claude.requiresLogin)

        await login.refresh(.claude, allowCredentialPrompt: true)

        let promptPermissions = await source.promptPermissions
        XCTAssertEqual(promptPermissions, [false, false, true])
        XCTAssertEqual(context.providers.claude.snapshot, recoveredSnapshot)
        XCTAssertNil(context.providers.claude.errorMessage)
    }

    func testCachedReadingBeforeLoginKeepsSignInPending() async throws {
        let snapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(-60))
        let source = ResultSource([.cached(snapshot, nextRefreshAt: Self.startedAt.addingTimeInterval(900))])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in }, now: { Self.startedAt })
        await openLogin(login)

        await login.refreshPendingLogins()

        XCTAssertNotNil(login.message(for: .claude))
        XCTAssertEqual(context.providers.claude.snapshot, snapshot)
        XCTAssertFalse(context.providers.claude.requiresLogin)
    }

    func testAutomaticSuccessFollowedByCachedRefreshClearsPendingLogin() async throws {
        let snapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(60))
        let source = ResultSource([
            .fetched(snapshot),
            .cached(snapshot, nextRefreshAt: Self.startedAt.addingTimeInterval(960))
        ])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in }, now: { Self.startedAt })
        await openLogin(login)

        let didFetch = await context.providers.claude.refresh()
        XCTAssertTrue(didFetch)
        XCTAssertNotNil(login.message(for: .claude))
        await login.refreshPendingLogins()

        XCTAssertNil(login.message(for: .claude))
        await login.refreshPendingLogins()
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 2)
    }

    func testNewerCollectorCacheClearsPendingLoginWithoutAnotherNetworkFetch() async throws {
        let snapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(60))
        let source = ResultSource([.cached(snapshot, nextRefreshAt: Self.startedAt.addingTimeInterval(960))])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in }, now: { Self.startedAt })
        await openLogin(login)

        await login.refresh(.claude)

        XCTAssertNil(login.message(for: .claude))
        XCTAssertNotNil(context.providers.claude.refreshMessage)
        await login.refreshPendingLogins()
        let fetchCount = await source.fetchCount
        XCTAssertEqual(fetchCount, 1)
    }

    func testAuthenticationFailureKeepsPendingLoginDespiteNewerSavedReading() async throws {
        let snapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(60))
        let source = ResultSource([.deferred(ClaudeClientError.unauthorized, snapshot: snapshot)])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        let login = ProviderLoginSession(providers: context.providers, openLogin: { _ in }, now: { Self.startedAt })
        await openLogin(login)

        await login.refreshPendingLogins()

        XCTAssertNotNil(login.message(for: .claude))
        XCTAssertTrue(context.providers.claude.requiresLogin)
        XCTAssertEqual(context.providers.claude.snapshot, snapshot)
    }

    func testLoginAttemptStartsBeforeOpeningTerminalCompletes() async throws {
        let snapshot = Self.snapshot(at: Self.startedAt.addingTimeInterval(5))
        let source = ResultSource([.cached(snapshot, nextRefreshAt: Self.startedAt.addingTimeInterval(905))])
        let context = try makeContext(source: source)
        defer { context.cleanUp() }
        var currentTime = Self.startedAt
        let login = ProviderLoginSession(
            providers: context.providers,
            openLogin: { _ in currentTime = Self.startedAt.addingTimeInterval(10) },
            now: { currentTime }
        )
        await openLogin(login)

        await login.refreshPendingLogins()

        XCTAssertNil(login.message(for: .claude))
    }

    private func openLogin(_ login: ProviderLoginSession) async {
        login.signIn(to: .claude)
        for _ in 0 ..< 100 {
            if !login.isOpening(.claude) { break }
            await Task.yield()
        }
        XCTAssertFalse(login.isOpening(.claude))
        XCTAssertNotNil(login.message(for: .claude))
    }

    private func makeContext(source: ResultSource) throws -> Context {
        let suite = "ProviderLoginSessionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let codex = UsageMonitor(
            defaults: defaults,
            historyDirectory: directory.appendingPathComponent("codex"),
            widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("codex-widget")),
            fetchUsage: { Self.snapshot(at: Self.startedAt) },
            recoveryDelaysNanoseconds: [], startsAutomatically: false
        )
        let claude = UsageMonitor(
            provider: .claude, defaults: defaults,
            historyDirectory: directory.appendingPathComponent("claude"),
            widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("claude-widget"), provider: .claude),
            fetchResult: { await source.fetch(allowCredentialPrompt: $0) },
            recoveryDelaysNanoseconds: [], startsAutomatically: false
        )
        return Context(
            suite: suite, defaults: defaults, directory: directory,
            providers: UsageProviders(defaults: defaults, codex: codex, claude: claude)
        )
    }

    private nonisolated static let startedAt = Date(timeIntervalSince1970: 1_900_000)

    private nonisolated static func snapshot(at date: Date) -> UsageSnapshot {
        UsageSnapshot(
            mainLimit: .init(limitId: "claude", name: "All models", window: .init(
                remainingPercent: 72, resetsAt: date.addingTimeInterval(4 * 86_400), durationMinutes: 10_080
            )),
            otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: date
        )
    }

    @MainActor private struct Context {
        let suite: String
        let defaults: UserDefaults
        let directory: URL
        let providers: UsageProviders

        func cleanUp() {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private actor ResultSource {
        let results: [UsageFetchResult]
        private(set) var promptPermissions: [Bool] = []

        var fetchCount: Int { promptPermissions.count }

        init(_ results: [UsageFetchResult]) { self.results = results }

        func fetch(allowCredentialPrompt: Bool) -> UsageFetchResult {
            defer { promptPermissions.append(allowCredentialPrompt) }
            return results[min(fetchCount, results.count - 1)]
        }
    }
}
