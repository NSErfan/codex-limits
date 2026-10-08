import AppKit
import Combine
import CodexWidgetKit
import SwiftUI

@MainActor
final class UsageURLHandler: NSObject, NSApplicationDelegate {
    var providers: UsageProviders?
    var login: ProviderLoginSession?
    var appearance: AppearanceSettings?
    private var usageWindow: NSWindowController?
    private var selection: AnyCancellable?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let provider = urls.compactMap(Self.provider(from:)).last,
              let providers, let login else { return }
        providers.selectedProvider = provider
        if let longestPeriod = provider.periods.last {
            UserDefaults.standard.set(longestPeriod.rawValue,
                                      forKey: UsageDashboardPreferences.selectionKey(for: provider))
        }
        showUsageWindow()
        application.activate(ignoringOtherApps: true)
        Task { await login.refresh(provider) }
    }

    private func showUsageWindow() {
        guard let providers, let login, let appearance else { return }
        if usageWindow == nil {
            let content = ProviderUsageWindow(providers: providers, login: login, appearance: appearance)
            let window = NSWindow(contentViewController: NSHostingController(rootView: content))
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 460, height: 300)
            window.contentMaxSize = NSSize(width: 460, height: CGFloat.greatestFiniteMagnitude)
            window.setContentSize(NSSize(width: 460, height: 740))
            window.center()
            usageWindow = NSWindowController(window: window)
            selection = providers.$selectedProvider.sink { [weak self] provider in
                self?.usageWindow?.window?.title = "\(provider.displayName) usage"
            }
        }
        usageWindow?.showWindow(nil)
        usageWindow?.window?.makeKeyAndOrderFront(nil)
    }

    nonisolated static func provider(from url: URL) -> UsageProvider? {
        guard url.scheme?.lowercased() == "codexlimits", url.host?.lowercased() == "usage",
              url.user == nil, url.password == nil, url.port == nil,
              url.pathComponents.count == 2 else { return nil }
        return UsageProvider(rawValue: url.lastPathComponent)
    }
}
