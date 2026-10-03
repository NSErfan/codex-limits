import CodexWidgetKit
import Combine
import Foundation

@MainActor
final class UsageProviders: ObservableObject {
    static let selectionKey = "selectedUsageProvider"

    @Published var selectedProvider: UsageProvider {
        didSet { defaults.set(selectedProvider.rawValue, forKey: Self.selectionKey) }
    }

    let codex: UsageMonitor
    let claude: UsageMonitor
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    var selectedMonitor: UsageMonitor {
        monitor(for: selectedProvider)
    }

    init(
        defaults: UserDefaults = .standard,
        codex: UsageMonitor? = nil,
        claude: UsageMonitor? = nil
    ) {
        self.defaults = defaults
        self.codex = codex ?? UsageMonitor(provider: .codex, defaults: defaults)
        self.claude = claude ?? UsageMonitor(provider: .claude, defaults: defaults)
        selectedProvider = defaults.string(forKey: Self.selectionKey)
            .flatMap(UsageProvider.init(rawValue:)) ?? .codex

        for monitor in [self.codex, self.claude] {
            monitor.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func monitor(for provider: UsageProvider) -> UsageMonitor {
        switch provider {
        case .codex: codex
        case .claude: claude
        }
    }

    func refreshAll() async {
        async let codexRefresh: Bool = codex.refresh()
        async let claudeRefresh: Bool = claude.refresh()
        _ = await (codexRefresh, claudeRefresh)
    }

    func updateSafetyBuffer(_ value: Double) {
        defaults.set(value, forKey: UsageMonitor.safetyBufferKey)
        codex.updateSafetyBuffer(value)
        claude.updateSafetyBuffer(value)
    }
}
