import Foundation

enum ReasoningEffortText {
    static func name(_ effort: String) -> String {
        effort == "unknown" ? "Not recorded" : effort.capitalized
    }

    static func description(_ effort: String) -> String {
        effort == "unknown" ? "Reasoning effort not recorded" : "\(effort.capitalized) reasoning effort"
    }
}
