import CodexWidgetKit
import SwiftUI

struct CodexLimitsApp: App {
    @NSApplicationDelegateAdaptor(UsageURLHandler.self) private var urlHandler
    @StateObject private var providers: UsageProviders
    @StateObject private var login: ProviderLoginSession
    @StateObject private var appearance: AppearanceSettings

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
                selectedProvider: Binding(
                    get: { providers.selectedProvider },
                    set: { provider in
                        if providers.select(provider) { Task { await login.refresh(provider) } }
                    }
                ),
                providerOptions: providers.enabledProviders,
                onSignIn: { login.signIn(to: providers.selectedProvider) },
                loginMessage: login.message(for: providers.selectedProvider),
                isOpeningLogin: login.isOpening(providers.selectedProvider)
            )
                .id(providers.selectedProvider)
                .environment(\.usageAccent, appearance.accent)
        } label: {
            ProviderMenuLabel(monitor: providers.selectedMonitor, displayMode: appearance.menuBarDisplayMode)
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
