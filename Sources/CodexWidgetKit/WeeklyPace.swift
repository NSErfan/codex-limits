import Foundation

public enum WeeklyPace: String, Codable, Sendable {
    case slowDown
    case onTrack
    case roomToUseMore

    public var title: String {
        switch self {
        case .slowDown: "Slow down"
        case .onTrack: "On track"
        case .roomToUseMore: "Room to use more"
        }
    }
}
