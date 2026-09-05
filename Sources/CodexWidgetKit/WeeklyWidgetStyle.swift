import SwiftUI

public enum WeeklyWidgetStyle {
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
