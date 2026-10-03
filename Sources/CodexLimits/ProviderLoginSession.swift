import AppKit
import Combine
import CodexWidgetKit

@MainActor
final class ProviderLoginSession: ObservableObject {
    @Published private var messages: [UsageProvider: String] = [:]
    @Published private var openingProviders: Set<UsageProvider> = []
    private var pendingProviders: Set<UsageProvider> = []
    private var refreshingProviders: Set<UsageProvider> = []
    private var activation: AnyCancellable?
    private let providers: UsageProviders

    init(providers: UsageProviders) {
        self.providers = providers
        activation = NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task { @MainActor in await self?.refreshPendingLogins() }
            }
    }

    func message(for provider: UsageProvider) -> String? { messages[provider] }

    func isOpening(_ provider: UsageProvider) -> Bool { openingProviders.contains(provider) }

    func signIn(to provider: UsageProvider) {
        guard !isOpening(provider) else { return }
        openingProviders.insert(provider)
        messages[provider] = nil
        Task {
            defer { openingProviders.remove(provider) }
            do {
                try await ProviderLogin.open(for: provider)
                pendingProviders.insert(provider)
                messages[provider] = "Finish signing in in Terminal, then refresh usage."
            } catch {
                messages[provider] = error.localizedDescription
            }
        }
    }

    func refreshPendingLogins() async {
        for provider in pendingProviders {
            await refresh(provider)
        }
    }

    func refresh(_ provider: UsageProvider) async {
        guard refreshingProviders.insert(provider).inserted else { return }
        defer { refreshingProviders.remove(provider) }
        let monitor = providers.monitor(for: provider)
        await monitor.refresh(allowCredentialPrompt: true)
        if !monitor.isRefreshing, monitor.snapshot != nil, monitor.errorMessage == nil, !monitor.requiresLogin {
            pendingProviders.remove(provider)
            messages[provider] = nil
        }
    }
}
