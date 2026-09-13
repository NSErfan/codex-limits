import AppKit
import CodexWidgetKit
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var scheme
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(LoginItem.preferenceKey) private var launchAtLogin = true
    @AppStorage(BackgroundCollection.preferenceKey) private var collectInBackground = false
    @State private var loginItemError: String?
    @State private var backgroundCollectionError: String?

    var body: some View {
        Form {
            Section("Appearance") {
                AccentColorPicker(appearance: appearance)
            }

            Section("General") {
                Stepper(value: $safetyBuffer, in: 1 ... 10, step: 1) {
                    Text("Reserve: \(Int(safetyBuffer))%")
                }
                .onChange(of: safetyBuffer) { _, value in
                    monitor.updateSafetyBuffer(value)
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
                Text("Choose a shared folder to combine usage history from your Macs.")
                    .foregroundStyle(.secondary)

                if let folderName = monitor.syncFolderName {
                    LabeledContent("Folder", value: folderName)
                    Button("Stop syncing") {
                        Task { await monitor.stopHistorySync() }
                    }
                } else {
                    Button("Choose folder…", action: chooseHistoryFolder)
                }

                Text("Use the same Codex account on every Mac connected to this folder.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose a private folder that only you can access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let syncErrorMessage = monitor.syncErrorMessage {
                    Label(syncErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .tint(appearance.accent.readableColor(scheme: scheme))
        .padding()
        .frame(width: 380)
        .frame(minHeight: 560, idealHeight: 720)
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

    private func chooseHistoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use this folder"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await monitor.connectHistoryFolder(directory) }
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
