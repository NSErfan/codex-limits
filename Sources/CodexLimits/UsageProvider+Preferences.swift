import CodexWidgetKit
import Foundation

extension UsageProvider {
    var historySubdirectory: String? { self == .codex ? nil : "Claude" }

    func preferenceKey(_ key: String) -> String {
        self == .codex ? key : "\(rawValue).\(key)"
    }

    var refreshInterval: TimeInterval {
        self == .claude ? ClaudeUsageCoordinator.minimumInterval : 600
    }

    func fetchUsage(allowCredentialPrompt: Bool = false) async throws -> UsageFetchResult {
        switch self {
        case .codex: .fetched(try await CodexClient.fetch())
        case .claude: try await ClaudeUsageCoordinator.shared().fetch(allowCredentialPrompt: allowCredentialPrompt)
        }
    }
}
