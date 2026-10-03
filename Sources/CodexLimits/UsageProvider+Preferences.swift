import CodexWidgetKit
import Foundation

extension UsageProvider {
    var historySubdirectory: String? { self == .codex ? nil : "Claude" }

    func preferenceKey(_ key: String) -> String {
        self == .codex ? key : "\(rawValue).\(key)"
    }

    func fetchUsage(allowCredentialPrompt: Bool = false) async throws -> UsageSnapshot {
        switch self {
        case .codex: try await CodexClient.fetch()
        case .claude: try await ClaudeClient.fetch(allowCredentialPrompt: allowCredentialPrompt)
        }
    }
}
