import AppKit
import CodexWidgetKit
import SwiftUI

@main
struct MenuBarLabelProbe: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @StateObject private var monitor: UsageMonitor
    private let mode: MenuBarDisplayMode

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let provider = UsageProvider(rawValue: arguments[1])!
        mode = MenuBarDisplayMode(rawValue: arguments[2])!
        let directory = URL(fileURLWithPath: arguments[3], isDirectory: true)
        let defaults = UserDefaults(suiteName: "MenuBarLabelProbe")!
        defaults.removePersistentDomain(forName: "MenuBarLabelProbe")
        let snapshot = UsageSnapshot(
            mainLimit: .init(limitId: provider.rawValue, name: "Weekly", window: .init(
                remainingPercent: 46, resetsAt: Date().addingTimeInterval(86_400), durationMinutes: 10_080
            )), otherLimits: [], tokenHistory: [], resetCredits: [], fetchedAt: Date()
        )
        let state = State(snapshot: snapshot, samples: [], previousStatus: nil)
        defaults.set(try! JSONEncoder().encode(state), forKey: provider.preferenceKey("usageState"))
        _monitor = StateObject(wrappedValue: UsageMonitor(
            provider: provider, defaults: defaults, historyDirectory: directory,
            widgetStore: WeeklyWidgetStore(directory: directory.appendingPathComponent("widget"), provider: provider),
            fetchUsage: { snapshot }, startsAutomatically: false
        ))
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Synthetic label validation")
        } label: {
            ProviderMenuLabel(monitor: monitor, displayMode: mode)
        }
        .menuBarExtraStyle(.window)
    }

    private struct State: Encodable {
        let snapshot: UsageSnapshot
        let samples: [UsageSample]
        let previousStatus: PaceStatus?
    }

    private final class Delegate: NSObject, NSApplicationDelegate {
        func applicationDidFinishLaunching(_ notification: Notification) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                self.inspect()
                UserDefaults.standard.removePersistentDomain(forName: "MenuBarLabelProbe")
                NSApp.terminate(nil)
            }
        }

        private func inspect() {
            let arguments = ProcessInfo.processInfo.arguments
            let output = URL(fileURLWithPath: arguments[3], isDirectory: true)
            var lines: [String] = []
            for window in NSApp.windows {
                lines.append("window: \(type(of: window)) \(window.frame)")
                if let root = window.contentView {
                    inspect(root, lines: &lines, output: output)
                }
            }
            try! lines.joined(separator: "\n").write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
        }

        private func inspect(_ view: NSView, lines: inout [String], output: URL) {
            if let button = view as? NSStatusBarButton {
                lines.append("button title: \(button.title); image: \(String(describing: button.image?.size)); frame: \(button.frame)")
                if let cell = button.cell {
                    lines.append("imageRect: \(cell.imageRect(forBounds: button.bounds)); titleRect: \(cell.titleRect(forBounds: button.bounds))")
                }
                if let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
                    button.cacheDisplay(in: button.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("button.png"))
                }
            }
            for child in view.subviews {
                inspect(child, lines: &lines, output: output)
            }
        }
    }
}
