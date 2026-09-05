import CodexWidgetKit
import SwiftUI

@main
enum CodexLimitsMain {
    @MainActor static func main() {
        if BackgroundCollector.shouldRun(arguments: CommandLine.arguments) {
            exit(BackgroundCollector.runBlocking())
        }
        CodexLimitsApp.main()
    }
}

struct CodexLimitsApp: App {
    @StateObject private var monitor: UsageMonitor
    @StateObject private var appearance: AppearanceSettings

    init() {
        // Must precede any preference or history access.
        LegacyBundleMigration.run()
        LoginItem.enableByDefault()
        BackgroundCollection.enableByDefault()
        _monitor = StateObject(wrappedValue: UsageMonitor())
        _appearance = StateObject(wrappedValue: AppearanceSettings())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(monitor: monitor)
                .environment(\.usageAccent, appearance.accent)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                Text(monitor.menuBarText)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(monitor: monitor, appearance: appearance)
                .environment(\.usageAccent, appearance.accent)
        }

        Window("Codex Limits Widgets", id: "widgets") {
            WidgetGalleryView(monitor: monitor)
                .environment(\.usageAccent, appearance.accent)
        }
        .windowResizability(.contentSize)
    }
}
