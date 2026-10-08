import CodexWidgetKit
import Foundation

extension UsageProvider {
    enum RefreshSchedule {
        /// Refresh on a fixed timer.
        case fixedInterval
        /// Refresh when the previous fetch says the next check is allowed.
        case fetchDeadline
    }

    /// Account allowance periods, shortest first.
    var periods: [UsagePeriod] {
        switch self {
        case .codex, .claude: [.fiveHour, .weekly]
        case .copilot: [.monthly]
        }
    }

    var historySubdirectory: String? {
        switch self {
        case .codex: nil
        case .claude: "Claude"
        case .copilot: "Copilot"
        }
    }

    var localHistoryDirectoryName: String {
        switch self {
        case .codex: "History"
        case .claude: "ClaudeHistory"
        case .copilot: "CopilotHistory"
        }
    }

    var executableName: String {
        switch self {
        case .codex: "codex"
        case .claude: "claude"
        case .copilot: "gh"
        }
    }

    var cliDisplayName: String {
        switch self {
        case .codex: "Codex CLI"
        case .claude: "Claude Code CLI"
        case .copilot: "GitHub CLI"
        }
    }

    func preferenceKey(_ key: String) -> String {
        self == .codex ? key : "\(rawValue).\(key)"
    }

    var refreshSchedule: RefreshSchedule {
        switch self {
        case .codex, .copilot: .fixedInterval
        case .claude: .fetchDeadline
        }
    }

    var refreshInterval: TimeInterval {
        switch self {
        case .codex, .copilot: 600
        case .claude: ClaudeUsageCoordinator.minimumInterval
        }
    }

    func fetchUsage() async throws -> UsageFetchResult {
        switch self {
        case .codex: .fetched(try await CodexClient.fetch())
        case .claude: try await ClaudeUsageCoordinator.shared().fetch()
        case .copilot: .fetched(try await CopilotClient.fetch())
        }
    }
}
