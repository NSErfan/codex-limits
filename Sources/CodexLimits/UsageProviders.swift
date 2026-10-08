import CodexWidgetKit
import Combine
import Foundation

@MainActor
final class UsageProviders: ObservableObject {
    static let selectionKey = "selectedUsageProvider"

    /// Always a provider that is on; change it with select(_:).
    @Published private(set) var selectedProvider: UsageProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Self.selectionKey) }
    }
    @Published private(set) var enabledProviders: [UsageProvider]

    let codex: UsageMonitor
    let claude: UsageMonitor
    let copilot: UsageMonitor
    private let defaults: UserDefaults
    private let widgetStore: WeeklyWidgetStore?
    private let reloadWidgets: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    var selectedMonitor: UsageMonitor {
        monitor(for: selectedProvider)
    }

    var monitors: [UsageMonitor] {
        UsageProvider.allCases.map(monitor(for:))
    }

    /// Monitors this object creates start only when their provider is on. Injected
    /// monitors keep the caller's lifecycle, except that turned-off ones are stopped.
    init(
        defaults: UserDefaults = .standard,
        codex: UsageMonitor? = nil,
        claude: UsageMonitor? = nil,
        copilot: UsageMonitor? = nil,
        widgetStore: WeeklyWidgetStore? = .shared(),
        reloadWidgets: @escaping () -> Void = WeeklyWidgetPublisher.reloadAllTimelines
    ) {
        self.defaults = defaults
        self.widgetStore = widgetStore
        self.reloadWidgets = reloadWidgets
        let enabled = ProviderEnablement.enabledProviders(in: defaults)
        enabledProviders = enabled
        func makeMonitor(_ provider: UsageProvider) -> UsageMonitor {
            UsageMonitor(provider: provider, defaults: defaults, startsAutomatically: enabled.contains(provider))
        }
        self.codex = codex ?? makeMonitor(.codex)
        self.claude = claude ?? makeMonitor(.claude)
        self.copilot = copilot ?? makeMonitor(.copilot)
        let saved = defaults.string(forKey: Self.selectionKey).flatMap(UsageProvider.init(rawValue:))
        selectedProvider = saved.flatMap { enabled.contains($0) ? $0 : nil } ?? enabled[0]

        for monitor in monitors {
            if !enabled.contains(monitor.provider) { monitor.stop() }
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
        switch provider {
        case .codex: codex
        case .claude: claude
        case .copilot: copilot
        }
    }

    func isEnabled(_ provider: UsageProvider) -> Bool {
        enabledProviders.contains(provider)
    }

    /// Returns false, leaving the selection unchanged, for a provider that is off.
    @discardableResult
    func select(_ provider: UsageProvider) -> Bool {
        guard isEnabled(provider) else { return false }
        if selectedProvider != provider { selectedProvider = provider }
        return true
    }

    /// Turning a provider off stops its checks and hides it; its saved readings and history stay.
    /// The last provider that is on can't be turned off.
    func setEnabled(_ enabled: Bool, for provider: UsageProvider) {
        guard ProviderEnablement.setEnabled(enabled, for: provider, in: defaults) else { return }
        enabledProviders = ProviderEnablement.enabledProviders(in: defaults)
        let monitor = monitor(for: provider)
        if isEnabled(provider) {
            Task { [weak self] in
                // A quick off-on-off must not leave a turned-off provider running.
                guard self?.isEnabled(provider) == true else { return }
                await monitor.start()
            }
        } else {
            monitor.stop()
            if selectedProvider == provider { selectedProvider = enabledProviders[0] }
        }
        shareEnablementWithWidgets()
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for monitor in monitors where isEnabled(monitor.provider) {
                group.addTask { _ = await monitor.refresh() }
            }
        }
    }

    func updateSafetyBuffer(_ value: Double) {
        defaults.set(value, forKey: UsageMonitor.safetyBufferKey)
        for monitor in monitors {
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
