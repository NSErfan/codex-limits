import AppKit
import Combine
import CodexWidgetKit

@MainActor
final class ProviderLoginSession: ObservableObject {
    @Published private var messages: [UsageProvider: String] = [:]
    @Published private var openingProviders: Set<UsageProvider> = []
    private var pendingLogins: [UsageProvider: Date] = [:]
    private var refreshingProviders: Set<UsageProvider> = []
    private var activation: AnyCancellable?
    private let providers: UsageProviders
    private let openLogin: @MainActor (UsageProvider) async throws -> Void
    private let now: () -> Date

    init(
        providers: UsageProviders,
        openLogin: @escaping @MainActor (UsageProvider) async throws -> Void = {
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
    }

    func message(for provider: UsageProvider) -> String? { messages[provider] }

    func isOpening(_ provider: UsageProvider) -> Bool { openingProviders.contains(provider) }

    func signIn(to provider: UsageProvider) {
        guard !isOpening(provider) else { return }
        let attemptStartedAt = now()
        openingProviders.insert(provider)
        messages[provider] = nil
        Task {
            defer { openingProviders.remove(provider) }
            do {
                try await openLogin(provider)
                pendingLogins[provider] = attemptStartedAt
                messages[provider] = "Finish signing in in Terminal, then refresh usage."
            } catch {
                messages[provider] = error.localizedDescription
            }
        }
    }

    func refreshPendingLogins() async {
        for provider in pendingLogins.keys {
            await refresh(provider)
        }
    }

    func refresh(_ provider: UsageProvider) async {
        guard refreshingProviders.insert(provider).inserted else { return }
        defer { refreshingProviders.remove(provider) }
        let monitor = providers.monitor(for: provider)
        let didFetch = await monitor.refresh(allowCredentialPrompt: true)
        let hasReadingAfterLogin = pendingLogins[provider].map { startedAt in
            !monitor.requiresLogin && monitor.snapshot.map { $0.fetchedAt >= startedAt } == true
        } ?? false
        if didFetch || hasReadingAfterLogin {
            pendingLogins[provider] = nil
            messages[provider] = nil
        }
    }
}
