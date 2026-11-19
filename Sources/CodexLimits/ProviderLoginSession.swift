import AppKit
import Combine

@MainActor
final class ProviderLoginSession: ObservableObject {
    @Published private var messages: [UsageAccount: String] = [:]
    @Published private var openingAccounts: Set<UsageAccount> = []
    private var pendingLogins: [UsageAccount: Date] = [:]
    private var refreshingAccounts: Set<UsageAccount> = []
    private var activation: AnyCancellable?
    private var enablement: AnyCancellable?
    private let providers: UsageProviders
    private let openLogin: @MainActor (UsageAccount) async throws -> Void
    private let now: () -> Date

    init(
        providers: UsageProviders,
        openLogin: @escaping @MainActor (UsageAccount) async throws -> Void = {
            try await ProviderLogin.open(for: $0)
        },
        now: @escaping () -> Date = { Date() }
    ) {
        self.providers = providers
        self.openLogin = openLogin
        self.now = now
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshPendingLogins() }
            }
        enablement = providers.$enabledAccounts
            .sink { [weak self] enabled in self?.forgetSignIns(except: enabled) }
    }

    func message(for account: UsageAccount) -> String? { messages[account] }

    func isOpening(_ account: UsageAccount) -> Bool { openingAccounts.contains(account) }

    func signIn(to account: UsageAccount) {
        guard providers.isAccountEnabled(account), !isOpening(account) else { return }
        let attemptStartedAt = now()
        openingAccounts.insert(account)
        messages[account] = nil
        Task {
            defer { openingAccounts.remove(account) }
            do {
                try await openLogin(account)
                guard providers.isAccountEnabled(account) else { return }
                pendingLogins[account] = attemptStartedAt
                messages[account] = "Finish signing in in Terminal, then refresh usage."
            } catch {
                if providers.isAccountEnabled(account) { messages[account] = error.localizedDescription }
            }
        }
    }

    /// Once an account is off, a pending sign-in should no longer trigger checks.
    private func forgetSignIns(except enabled: [UsageAccount]) {
        pendingLogins = pendingLogins.filter { enabled.contains($0.key) }
        messages = messages.filter { enabled.contains($0.key) }
    }

    func refreshPendingLogins() async {
        for account in pendingLogins.keys {
            await refresh(account)
        }
    }

    func refresh(_ account: UsageAccount) async {
        guard providers.isAccountEnabled(account), refreshingAccounts.insert(account).inserted else { return }
        defer { refreshingAccounts.remove(account) }
        let monitor = providers.monitor(forAccount: account)
        let didFetch = await monitor.refresh()
        let hasReadingAfterLogin = pendingLogins[account].map { startedAt in
            !monitor.requiresLogin && monitor.snapshot.map { $0.fetchedAt >= startedAt } == true
        } ?? false
        if didFetch || hasReadingAfterLogin {
            pendingLogins[account] = nil
            messages[account] = nil
        }
    }
}
