import AppKit
import SwiftUI

enum AccentContrast {
    struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }

        init(_ color: NSColor) {
            let rgb = color.usingColorSpace(.sRGB)!
            red = min(1, max(0, Double(rgb.redComponent)))
            green = min(1, max(0, Double(rgb.greenComponent)))
            blue = min(1, max(0, Double(rgb.blueComponent)))
        }

        var color: Color { Color(.sRGB, red: red, green: green, blue: blue) }

        var luminance: Double {
            // https://www.w3.org/TR/WCAG21/relative-luminance.html
            func linear(_ value: Double) -> Double {
                value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrast(with other: Self) -> Double {
            (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
        }

        func mixed(with other: Self, amount: Double) -> Self {
            Self(
                red: red + (other.red - red) * amount,
                green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount
            )
        }
    }

    static func readable(_ color: Color, scheme: ColorScheme) -> Color {
        var background = RGB(red: 1, green: 1, blue: 1)
        // Resolve the native background for the view's appearance, which can
        // differ from the app's appearance in widget and gallery rendering.
        NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
            background = RGB(.windowBackgroundColor)
        }
        return foreground(RGB(NSColor(color)), background: background, dark: scheme == .dark).color
    }

    static func foreground(_ tint: RGB, background: RGB, dark: Bool) -> RGB {
        // Check the native surface and the maximum overlap of both tint washes.
        let wash = dark ? 1 - (1 - 0.13) * (1 - 0.12) : 1 - (1 - 0.08) * (1 - 0.05)
        let surfaces = [background, background.mixed(with: tint, amount: wash)]
        func isReadable(_ candidate: RGB) -> Bool {
            surfaces.allSatisfy { surface in
                candidate.contrast(with: surface) >= 4.5
                    && candidate.contrast(with: surface.mixed(with: candidate, amount: 0.12)) >= 4.5
                    && candidate.contrast(with: surface.mixed(with: candidate, amount: 0.23)) >= 3
            }
        }
        if isReadable(tint) { return tint }

        // Shift toward white/black only as far as necessary. This retains the
        // chosen hue and handles achromatic choices such as pure black, too.
        let endpoint = dark ? RGB(red: 1, green: 1, blue: 1) : RGB(red: 0, green: 0, blue: 0)
        var lower = 0.0
        var upper = 1.0
        for _ in 0 ..< 24 {
            let middle = (lower + upper) / 2
            if isReadable(tint.mixed(with: endpoint, amount: middle)) {
                upper = middle
            } else {
                lower = middle
            }
        }
        return tint.mixed(with: endpoint, amount: upper)
    }
}
