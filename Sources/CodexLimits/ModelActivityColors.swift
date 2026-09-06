import SwiftUI

/// Category colors stay stable across intervals and filters, independently of the app tint.
struct ModelActivityColors {
    static func model(_ name: String, scheme: ColorScheme) -> Color {
        // Swift's Hasher is randomized per launch; use a deterministic hash for category identity.
        let hash = name.utf8.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1) }
        return color(hue: Double(hash % 360) / 360, scheme: scheme)
    }

    static func effort(_ name: String, scheme: ColorScheme) -> Color {
        let hues: [String: Double] = ["none": 0.52, "minimal": 0.46, "low": 0.38,
                                      "medium": 0.12, "high": 0.07, "xhigh": 0.96,
                                      "max": 0.83, "ultra": 0.72, "unknown": 0.60]
        return color(hue: hues[name] ?? 0.60, scheme: scheme)
    }

    private static func color(hue: Double, scheme: ColorScheme) -> Color {
        Color(hue: hue, saturation: scheme == .dark ? 0.55 : 0.72,
              brightness: scheme == .dark ? 0.95 : 0.68)
    }
}
