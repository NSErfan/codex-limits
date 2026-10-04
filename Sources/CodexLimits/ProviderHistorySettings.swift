import AppKit
import SwiftUI

struct ProviderHistorySettings: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        Text("Choose a shared folder to combine \(monitor.provider.displayName) usage history from your Macs.")
            .foregroundStyle(.secondary)

        if let folderName = monitor.syncFolderName {
            LabeledContent("Folder", value: folderName)
            Button("Stop syncing") {
                Task { await monitor.stopHistorySync() }
            }
        } else {
            Button("Choose folder…", action: chooseHistoryFolder)
        }

        Text("Use the same \(monitor.provider.displayName) account on every Mac connected to this folder.")
            .font(.caption)
            .foregroundStyle(.secondary)
        Text("Choose a private folder that only you can access.")
            .font(.caption)
            .foregroundStyle(.secondary)

        if let message = monitor.syncErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption)
                .foregroundStyle(.secondary)
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
