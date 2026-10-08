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
    let copilot: UsageMonitor
    private let defaults: UserDefaults
    private var cancellables: Set<AnyCancellable> = []

    var selectedMonitor: UsageMonitor {
        monitor(for: selectedProvider)
    }

    var monitors: [UsageMonitor] {
        UsageProvider.allCases.map(monitor(for:))
    }

    init(
        defaults: UserDefaults = .standard,
        codex: UsageMonitor? = nil,
        claude: UsageMonitor? = nil,
        copilot: UsageMonitor? = nil
    ) {
        self.defaults = defaults
        self.codex = codex ?? UsageMonitor(provider: .codex, defaults: defaults)
        self.claude = claude ?? UsageMonitor(provider: .claude, defaults: defaults)
        self.copilot = copilot ?? UsageMonitor(provider: .copilot, defaults: defaults)
        selectedProvider = defaults.string(forKey: Self.selectionKey)
            .flatMap(UsageProvider.init(rawValue:)) ?? .codex

        for monitor in monitors {
            monitor.objectWillChange
                .sink { [weak self] _ in self?.objectWillChange.send() }
                .store(in: &cancellables)
        }
    }

    func monitor(for provider: UsageProvider) -> UsageMonitor {
        switch provider {
        case .codex: codex
        case .claude: claude
        case .copilot: copilot
        }
    }

    func refreshAll() async {
        await withTaskGroup(of: Void.self) { group in
            for monitor in monitors {
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
}
