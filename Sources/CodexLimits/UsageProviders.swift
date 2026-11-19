import CodexWidgetKit
import Combine
import Foundation

@MainActor
final class UsageProviders: ObservableObject {
    static let selectionKey = "selectedUsageProvider"
    static let accountOrderKey = "usageAccountOrder"

    enum MoveDirection: Int {
        case earlier = -1
        case later = 1
    }

    /// Always an account that is on; change it with selectAccount(_:).
    @Published private(set) var selectedAccount: UsageAccount {
        didSet { defaults.set(selectedAccount.rawValue, forKey: Self.selectionKey) }
    }
    @Published private(set) var enabledAccounts: [UsageAccount]

    let codex: UsageMonitor
    private let secondCodex: UsageMonitor
    let claude: UsageMonitor
    let copilot: UsageMonitor
    private let defaults: UserDefaults
    private let widgetStore: WeeklyWidgetStore?
    private let reloadWidgets: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    var selectedMonitor: UsageMonitor {
        monitor(forAccount: selectedAccount)
    }

    var selectedProvider: UsageProvider { selectedAccount.provider }
    var enabledProviders: [UsageProvider] { enabledAccounts.filter { $0 != .secondaryCodex }.map(\.provider) }
    var isSecondCodexEnabled: Bool { defaults.bool(forKey: UsageAccount.secondCodexEnabledKey) }

    private var monitors: [UsageMonitor] {
        [codex, secondCodex, claude, copilot]
    }

    /// Monitors this object creates start only when their provider is on. Injected
    /// monitors keep the caller's lifecycle, except that turned-off ones are stopped.
    init(
        defaults: UserDefaults = .standard,
        codex: UsageMonitor? = nil,
        secondCodex: UsageMonitor? = nil,
        claude: UsageMonitor? = nil,
        copilot: UsageMonitor? = nil,
        widgetStore: WeeklyWidgetStore? = .shared(),
        reloadWidgets: @escaping () -> Void = WeeklyWidgetPublisher.reloadAllTimelines
    ) {
        self.defaults = defaults
        self.widgetStore = widgetStore
        self.reloadWidgets = reloadWidgets
        let enabled = Self.enabledAccounts(in: defaults)
        enabledAccounts = enabled
        func makeMonitor(_ account: UsageAccount) -> UsageMonitor {
            UsageMonitor(account: account, defaults: defaults, startsAutomatically: enabled.contains(account))
        }
        self.codex = codex ?? makeMonitor(.primaryCodex)
        self.secondCodex = secondCodex ?? makeMonitor(.secondaryCodex)
        self.claude = claude ?? makeMonitor(.claude)
        self.copilot = copilot ?? makeMonitor(.copilot)
        let saved = defaults.string(forKey: Self.selectionKey).flatMap(UsageAccount.init(rawValue:))
        selectedAccount = saved.flatMap { enabled.contains($0) ? $0 : nil } ?? enabled[0]

        for monitor in monitors {
            if !enabled.contains(monitor.account) { monitor.stop() }
            monitor.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
        // Also repairs widget sharing after a failed write or an upgrade.
        if let widgetStore, widgetStore.readDisabledProviders() != disabledProviders {
            shareEnablementWithWidgets()
        }
    }

    func monitor(for provider: UsageProvider) -> UsageMonitor {
        monitor(forAccount: UsageAccount(provider: provider))
    }

    func monitor(forAccount account: UsageAccount) -> UsageMonitor {
        switch account {
        case .primaryCodex: codex
        case .secondaryCodex: secondCodex
        case .claude: claude
        case .copilot: copilot
        }
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        isAccountEnabled(UsageAccount(provider: provider))
    }

    func isAccountEnabled(_ account: UsageAccount) -> Bool {
        enabledAccounts.contains(account)
    }

    @discardableResult
    func select(_ provider: UsageProvider) -> Bool {
        selectAccount(UsageAccount(provider: provider))
    }

    /// Returns false, leaving the selection unchanged, for an account that is off.
    @discardableResult
    func selectAccount(_ account: UsageAccount) -> Bool {
        guard isAccountEnabled(account) else { return false }
        if selectedAccount != account { selectedAccount = account }
        return true
    }

    /// Turning a provider off stops its checks and hides it; its saved readings and history stay.
    /// The last provider that is on can't be turned off.
    func setEnabled(_ enabled: Bool, for provider: UsageProvider) {
        guard ProviderEnablement.setEnabled(enabled, for: provider, in: defaults) else { return }
        updateEnabledAccounts()
        shareEnablementWithWidgets()
    }

    func setSecondCodexEnabled(_ enabled: Bool) {
        guard enabled != isSecondCodexEnabled else { return }
        defaults.set(enabled, forKey: UsageAccount.secondCodexEnabledKey)
        updateEnabledAccounts()
    }

    func moveAccount(_ account: UsageAccount, _ direction: MoveDirection) {
        guard let current = enabledAccounts.firstIndex(of: account) else { return }
        let target = current + direction.rawValue
        guard enabledAccounts.indices.contains(target) else { return }
        let other = enabledAccounts[target]
        var order = Self.accountOrder(in: defaults)
        guard let source = order.firstIndex(of: account), let destination = order.firstIndex(of: other) else { return }
        order.swapAt(source, destination)
        defaults.set(order.map(\.rawValue), forKey: Self.accountOrderKey)
        enabledAccounts = Self.enabledAccounts(in: defaults)
    }

    private func updateEnabledAccounts() {
        let previous = enabledAccounts
        let enabled = Self.enabledAccounts(in: defaults)
        enabledAccounts = enabled
        if !enabled.contains(selectedAccount) { selectedAccount = enabled[0] }
        for account in previous where !enabled.contains(account) {
            monitor(forAccount: account).stop()
        }
        for account in enabled where !previous.contains(account) {
            let monitor = monitor(forAccount: account)
            Task { [weak self] in
                guard self?.isAccountEnabled(account) == true else { return }
                await monitor.start()
            }
        }
    }

    private static func enabledAccounts(in defaults: UserDefaults) -> [UsageAccount] {
        let enabled = Set(UsageAccount.enabledAccounts(
            providers: ProviderEnablement.enabledProviders(in: defaults),
            secondCodexEnabled: defaults.bool(forKey: UsageAccount.secondCodexEnabledKey)
        ))
        return accountOrder(in: defaults).filter(enabled.contains)
    }

    private static func accountOrder(in defaults: UserDefaults) -> [UsageAccount] {
        let saved = (defaults.stringArray(forKey: accountOrderKey) ?? []).compactMap(UsageAccount.init(rawValue:))
        var seen: Set<UsageAccount> = []
        return (saved + UsageAccount.allCases).filter { seen.insert($0).inserted }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for monitor in enabledAccounts.map(monitor(forAccount:)) {
                group.addTask { _ = await monitor.refresh() }
            }
        }
    }

    func updateSafetyBuffer(_ value: Double) {
        defaults.set(value, forKey: UsageMonitor.safetyBufferKey)
        for monitor in monitors where monitor.account != .secondaryCodex || isSecondCodexEnabled {
            monitor.updateSafetyBuffer(value)
        }
    }

    private var disabledProviders: Set<UsageProvider> {
        Set(UsageProvider.allCases).subtracting(enabledProviders)
    }

    private func shareEnablementWithWidgets() {
        guard let widgetStore else { return }
        do {
            try widgetStore.writeDisabledProviders(disabledProviders)
            reloadWidgets()
        } catch {
            // Widgets keep their last state; the next launch retries the write.
        }
    }
}
