import SwiftUI

struct ProviderUsageWindow: View {
    @ObservedObject var providers: UsageProviders
    @ObservedObject var login: ProviderLoginSession
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView {
            MenuContentView(
                monitor: providers.selectedMonitor,
                selectedProvider: Binding(
                    get: { providers.selectedProvider },
                    set: { provider in
                        providers.selectedProvider = provider
                        Task { await login.refresh(provider) }
                    }
                ),
                onSignIn: { login.signIn(to: providers.selectedProvider) },
                loginMessage: login.message(for: providers.selectedProvider),
                isOpeningLogin: login.isOpening(providers.selectedProvider),
                showsFooterActions: false,
                refreshesOnAppear: false
            )
            .id(providers.selectedProvider)
        }
        .frame(width: 460)
        .environment(\.usageAccent, appearance.accent)
    }
}
