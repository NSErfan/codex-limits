import CodexWidgetKit
import SwiftUI

struct CodexLimitsApp: App {
    @NSApplicationDelegateAdaptor(UsageURLHandler.self) private var urlHandler
    @StateObject private var providers: UsageProviders
    @StateObject private var login: ProviderLoginSession
    @StateObject private var appearance: AppearanceSettings
    @State private var settingsWindowPresenter = SettingsWindowPresenter()

    init() {
        // Must precede any preference or history access.
        LegacyBundleMigration.run()
        LoginItem.enableByDefault()
        BackgroundCollection.enableByDefault()
        let providers = UsageProviders()
        let login = ProviderLoginSession(providers: providers)
        let appearance = AppearanceSettings()
        _providers = StateObject(wrappedValue: providers)
        _login = StateObject(wrappedValue: login)
        _appearance = StateObject(wrappedValue: appearance)
        urlHandler.providers = providers
        urlHandler.login = login
        urlHandler.appearance = appearance
    }

    var body: some Scene {
        MenuBarExtra {
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
                settingsWindowPresenter: settingsWindowPresenter
            )
                .id(providers.selectedAccount)
                .environment(\.usageAccent, appearance.accent)
        } label: {
            ProviderMenuLabel(
                monitor: providers.selectedMonitor,
                displayMode: appearance.menuBarDisplayMode,
                usageWindow: appearance.menuBarUsageWindow(for: providers.selectedProvider)
            )
        }
        .menuBarExtraStyle(.window)

        activityWindow(for: .primary)
        activityWindow(for: .secondary)

        Settings {
            SettingsView(providers: providers, appearance: appearance, login: login)
                .environment(\.usageAccent, appearance.accent)
                .background(SettingsWindowRegistration(presenter: settingsWindowPresenter))
        }
    }

    private func activityWindow(for profile: CodexProfile) -> some Scene {
        let account: UsageAccount = profile == .secondary ? .secondaryCodex : .primaryCodex
        return Window(ModelActivityWindow.title(for: profile), id: ModelActivityWindow.sceneID(for: profile)) {
            ModelActivityWindow(profile: profile, monitor: providers.monitor(forAccount: account),
                                isAccountEnabled: providers.isAccountEnabled(account))
                .environment(\.usageAccent, appearance.accent)
        }
        .defaultSize(width: 1_080, height: 880)
        .windowResizability(.contentMinSize)
    }
}

@main
enum CodexLimitsMain {
    @MainActor static func main() {
        if BackgroundCollector.shouldRun(arguments: CommandLine.arguments) {
            exit(BackgroundCollector.runBlocking())
        }
        CodexLimitsApp.main()
    }
}
