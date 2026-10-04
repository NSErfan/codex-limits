public enum UsageProvider: String, Codable, CaseIterable, Sendable, Identifiable {
    case codex
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .codex: "Codex"
        case .claude: "Claude Code"
        }
    }
}
