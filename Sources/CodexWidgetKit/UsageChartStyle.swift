import SwiftUI

public enum UsageChartStyle {
    public static let actualStroke = StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round)
    public static let guideStroke = StrokeStyle(lineWidth: 1, dash: [3, 4])
    public static let gridStroke = StrokeStyle(lineWidth: 1, dash: [2, 4])
    public static let guide = Color.secondary.opacity(0.5)
    public static let grid = Color.primary.opacity(0.07)
    public static let axisFont = Font.system(size: 9, weight: .medium, design: .monospaced)

    public static func area(_ accent: Color) -> LinearGradient {
        LinearGradient(
            colors: [accent.opacity(0.23), accent.opacity(0.01)],
            startPoint: .top, endPoint: .bottom
        )
    }

    public static func today(scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.75, green: 0.70, blue: 0.95) : Color(red: 0.46, green: 0.36, blue: 0.65)
    }

    public static func accent(for remaining: Double?, scheme: ColorScheme) -> Color {
        if let remaining, remaining <= 10 {
            return scheme == .dark ? Color(red: 1, green: 0.55, blue: 0.40) : Color(red: 0.72, green: 0.22, blue: 0.10)
        }
        if let remaining, remaining <= 25 {
            return scheme == .dark ? Color(red: 1, green: 0.78, blue: 0.38) : Color(red: 0.57, green: 0.36, blue: 0.04)
        }
        return scheme == .dark ? Color(red: 0.57, green: 0.94, blue: 0.79) : Color(red: 0.10, green: 0.40, blue: 0.32)
    }
}
