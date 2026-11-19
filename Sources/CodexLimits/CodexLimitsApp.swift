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

        Window("Model activity", id: "model-activity") {
            ModelActivityWindow(monitor: providers.codex, isProviderEnabled: providers.isEnabled(.codex))
                .environment(\.usageAccent, appearance.accent)
        }
        .defaultSize(width: 1_080, height: 880)
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(providers: providers, appearance: appearance, login: login)
                .environment(\.usageAccent, appearance.accent)
                .background(SettingsWindowRegistration(presenter: settingsWindowPresenter))
        }
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
