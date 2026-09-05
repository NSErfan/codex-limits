import SwiftUI

/// A portable selection shared by the app and its widget extension.
public enum UsageAccent: Codable, Equatable, Sendable {
    case automatic, mint, blue, indigo, violet, rose, orange
    case custom(red: Double, green: Double, blue: Double)

    public static let presets: [Self] = [.automatic, .mint, .blue, .indigo, .violet, .rose, .orange]

    public var name: String {
        switch self {
        case .automatic: "Automatic"
        case .mint: "Mint"
        case .blue: "Blue"
        case .indigo: "Indigo"
        case .violet: "Violet"
        case .rose: "Rose"
        case .orange: "Orange"
        case .custom: "Custom"
        }
    }

    public var isValid: Bool {
        guard case let .custom(red, green, blue) = self else { return true }
        return [red, green, blue].allSatisfy { $0.isFinite && (0 ... 1).contains($0) }
    }

    public func color(scheme: ColorScheme) -> Color {
        let dark = scheme == .dark
        switch self {
        case .automatic, .mint:
            return dark ? Color(red: 0.57, green: 0.94, blue: 0.79) : Color(red: 0.10, green: 0.40, blue: 0.32)
        case .blue:
            return dark ? Color(red: 0.48, green: 0.77, blue: 1) : Color(red: 0.08, green: 0.36, blue: 0.68)
        case .indigo:
            return dark ? Color(red: 0.65, green: 0.68, blue: 1) : Color(red: 0.30, green: 0.32, blue: 0.72)
        case .violet:
            return dark ? Color(red: 0.81, green: 0.64, blue: 1) : Color(red: 0.48, green: 0.25, blue: 0.68)
        case .rose:
            return dark ? Color(red: 1, green: 0.63, blue: 0.77) : Color(red: 0.68, green: 0.22, blue: 0.40)
        case .orange:
            return dark ? Color(red: 1, green: 0.76, blue: 0.48) : Color(red: 0.62, green: 0.32, blue: 0.08)
        case let .custom(red, green, blue):
            return isValid ? Color(.sRGB, red: red, green: green, blue: blue) : Self.mint.color(scheme: scheme)
        }
    }

    /// For foregrounds and controls; `color` retains the exact picker selection.
    public func readableColor(scheme: ColorScheme) -> Color {
        AccentContrast.readable(color(scheme: scheme), scheme: scheme)
    }
}

private struct UsageAccentKey: EnvironmentKey {
    static let defaultValue = UsageAccent.automatic
}

public extension EnvironmentValues {
    var usageAccent: UsageAccent {
        get { self[UsageAccentKey.self] }
        set { self[UsageAccentKey.self] = newValue }
    }
}
