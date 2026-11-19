import SwiftUI

struct ProviderUsageWindow: View {
    @ObservedObject var providers: UsageProviders
    @ObservedObject var login: ProviderLoginSession
    @ObservedObject var appearance: AppearanceSettings

    var body: some View {
        ScrollView {
            MenuContentView(
                monitor: providers.selectedMonitor,
                selectedAccount: Binding(
                    get: { providers.selectedAccount },
                    set: { account in
                        if providers.selectAccount(account) { Task { await login.refresh(account) } }
                    }
                ),
                accountOptions: providers.enabledAccounts,
                onSignIn: { login.signIn(to: providers.selectedAccount) },
                loginMessage: login.message(for: providers.selectedAccount),
                isOpeningLogin: login.isOpening(providers.selectedAccount),
                showsFooterActions: false,
                refreshesOnAppear: false
            )
            .id(providers.selectedAccount)
        }
        .frame(width: 460)
        .environment(\.usageAccent, appearance.accent)
    }
}
