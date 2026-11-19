//
//  UsageAccount.swift
//  CodexLimits
//
//  Created by Erfan on 19/11/26.
//

import CodexWidgetKit
import Foundation

enum UsageAccount: String, CaseIterable, Identifiable, Sendable {
    case primaryCodex = "codex"
    case secondaryCodex = "codex-secondary"
    case claude
    case copilot

    static let secondCodexEnabledKey = "secondCodexEnabled"

    init(provider: UsageProvider) {
        switch provider {
        case .codex: self = .primaryCodex
        case .claude: self = .claude
        case .copilot: self = .copilot
        }
    }

    var id: String { rawValue }

    var provider: UsageProvider {
        switch self {
        case .primaryCodex, .secondaryCodex: .codex
        case .claude: .claude
        case .copilot: .copilot
        }
    }

    var displayName: String { self == .secondaryCodex ? "Codex 2" : provider.displayName }
    var codexProfile: CodexProfile? {
        switch self {
        case .primaryCodex: .primary
        case .secondaryCodex: .secondary
        case .claude, .copilot: nil
        }
    }

    var publishesWeeklyWidget: Bool { self != .secondaryCodex && provider.periods.contains(.weekly) }
    var historySubdirectory: String? { self == .secondaryCodex ? "Codex 2" : provider.historySubdirectory }
    var localHistoryDirectoryName: String {
        self == .secondaryCodex ? "CodexSecondaryHistory" : provider.localHistoryDirectoryName
    }

    static func enabledAccounts(providers: [UsageProvider], secondCodexEnabled: Bool) -> [Self] {
        providers.flatMap { provider in
            let primary = Self(provider: provider)
            return provider == .codex && secondCodexEnabled ? [primary, .secondaryCodex] : [primary]
        }
    }

    func preferenceKey(_ key: String) -> String {
        self == .secondaryCodex ? "\(rawValue).\(key)" : provider.preferenceKey(key)
    }

    func fetchUsage() async throws -> UsageFetchResult {
        if self == .secondaryCodex {
            return .fetched(try await CodexClient.fetch(profile: .secondary))
        }
        return try await provider.fetchUsage()
    }
}
