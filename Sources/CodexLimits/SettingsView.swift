import AppKit
import CodexWidgetKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var providers: UsageProviders
    @ObservedObject var appearance: AppearanceSettings
    @ObservedObject var login: ProviderLoginSession
    @Environment(\.colorScheme) private var scheme
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(LoginItem.preferenceKey) private var launchAtLogin = true
    @AppStorage(BackgroundCollection.preferenceKey) private var collectInBackground = false
    @State private var loginItemError: String?
    @State private var backgroundCollectionError: String?

    var body: some View {
        Form {
            Section("Accounts") {
                ProviderAccountSettings(monitor: providers.codex, login: login)
                ProviderAccountSettings(monitor: providers.claude, login: login)
                Text("Uses your existing CLI sign-ins. Sign in opens the official CLI in Terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                Picker("Menu bar", selection: Binding(
                    get: { appearance.menuBarDisplayMode },
                    set: appearance.setMenuBarDisplayMode
                )) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                AccentColorPicker(appearance: appearance)
            }

            Section("General") {
                Stepper(value: $safetyBuffer, in: 1 ... 10, step: 1) {
                    Text("Reserve: \(Int(safetyBuffer))%")
                }
                .onChange(of: safetyBuffer) { _, value in
                    providers.updateSafetyBuffer(value)
                }

                Text("Amount of this period’s allowance you want left at your pacing target.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: updateLaunchAtLogin
                ))

                if let loginItemError {
                    Text(loginItemError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Background updates") {
                Toggle("Record usage while the app is closed", isOn: Binding(
                    get: { collectInBackground },
                    set: updateBackgroundCollection
                ))

                Text("Checks for usage about every 15 minutes while the app is closed to help fill your usage history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if BackgroundCollection.service.status == .requiresApproval {
                    Label(
                        "Allow Codex Limits to run in the background in System Settings to enable these updates.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let backgroundCollectionError {
                    Text(backgroundCollectionError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History sync") {
                ProviderPicker(selection: $providers.selectedProvider)
                ProviderHistorySettings(monitor: providers.selectedMonitor)
            }
        }
        .formStyle(.grouped)
        .tint(appearance.accent.readableColor(scheme: scheme))
        .padding()
        .frame(width: 440)
        .frame(minHeight: 620, idealHeight: 800)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginItemError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "Couldn’t change whether Codex Limits opens at login. Try again."
        }
    }

    private func updateBackgroundCollection(_ enabled: Bool) {
        do {
            if enabled, BackgroundCollection.service.status != .enabled {
                try BackgroundCollection.service.register()
            } else if !enabled, BackgroundCollection.service.status == .enabled {
                try BackgroundCollection.service.unregister()
            }
            collectInBackground = enabled
            backgroundCollectionError = nil
        } catch {
            collectInBackground = BackgroundCollection.service.status == .enabled
            backgroundCollectionError = "Couldn’t change background updates. Try again."
        }
    }

}

enum BackgroundCollection {
    static let preferenceKey = "collectInBackground"
    static let agentPlistName = "com.github.nserfan.CodexLimits.collector.plist"

    static var service: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    static func enableByDefault() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) == nil else { return }
        // Registration pins the agent to this bundle's location, so a bare
        // `swift run` binary must not claim it before the installed app can.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if service.status != .enabled {
                try service.register()
            }
            defaults.set(true, forKey: preferenceKey)
        } catch {
            defaults.set(false, forKey: preferenceKey)
        }
    }
}

enum LoginItem {
    static let preferenceKey = "launchAtLogin"

    static func enableByDefault() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) == nil else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            defaults.set(true, forKey: preferenceKey)
        } catch {
            defaults.set(false, forKey: preferenceKey)
        }
    }
}
