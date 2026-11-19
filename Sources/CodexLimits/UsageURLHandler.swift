import AppKit
import Combine
import SwiftUI

@MainActor
final class UsageURLHandler: NSObject, NSApplicationDelegate {
    var providers: UsageProviders?
    var login: ProviderLoginSession?
    var appearance: AppearanceSettings?
    private var usageWindow: NSWindowController?
    private var selection: AnyCancellable?

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let account = urls.compactMap(Self.account(from:)).last,
              let providers, let login else { return }
        // Links from disabled accounts still open the window on an enabled one.
        let selected = providers.selectAccount(account)
        if selected, let longestPeriod = account.provider.periods.last {
            UserDefaults.standard.set(longestPeriod.rawValue,
                                      forKey: UsageDashboardPreferences.selectionKey(for: account))
        }
        showUsageWindow()
        application.activate(ignoringOtherApps: true)
        if selected { Task { await login.refresh(account) } }
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
            selection = providers.$selectedAccount.sink { [weak self] account in
                self?.usageWindow?.window?.title = "\(account.displayName) usage"
            }
        }
        usageWindow?.showWindow(nil)
        usageWindow?.window?.makeKeyAndOrderFront(nil)
    }

    nonisolated static func account(from url: URL) -> UsageAccount? {
        guard url.scheme?.lowercased() == "codexlimits", url.host?.lowercased() == "usage",
              url.user == nil, url.password == nil, url.port == nil,
              url.pathComponents.count == 2 else { return nil }
        return UsageAccount(rawValue: url.lastPathComponent)
    }
}
