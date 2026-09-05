import AppKit
import SwiftUI
import XCTest
@testable import CodexWidgetKit

final class AccentContrastTests: XCTestCase {
    typealias RGB = AccentContrast.RGB

    func testLuminanceMatchesKnownSRGBValues() {
        let black = RGB(red: 0, green: 0, blue: 0)
        let white = RGB(red: 1, green: 1, blue: 1)
        XCTAssertEqual(black.contrast(with: white), 21, accuracy: 0.000001)
        XCTAssertEqual(RGB(red: 0.5, green: 0.5, blue: 0.5).luminance, 0.21404114, accuracy: 0.000001)
    }

    func testExtremeAndSaturatedColorsRemainReadableOnSurfacesAndSelections() {
        // Include black, white, near-black, grays, and saturated RGB mixtures.
        let channels = [0.0, 0.02, 0.25, 0.5, 0.75, 1.0]
        for dark in [true, false] {
            let level = dark ? 0.12 : 0.96
            let base = RGB(red: level, green: level, blue: level)
            for red in channels {
                for green in channels {
                    for blue in channels {
                        let tint = RGB(red: red, green: green, blue: blue)
                        let foreground = AccentContrast.foreground(tint, background: base, dark: dark)
                        // Sample intermediate positions within the tint gradient,
                        // not just the endpoints checked by the implementation.
                        let maxWash = dark ? 0.2344 : 0.126
                        for fraction in [0.0, 0.25, 0.5, 0.75, 1.0] {
                            let surface = base.mixed(with: tint, amount: maxWash * fraction)
                            XCTAssertGreaterThanOrEqual(foreground.contrast(with: surface), 4.5 - 0.00001)
                            let selectedTab = surface.mixed(with: foreground, amount: 0.12)
                            XCTAssertGreaterThanOrEqual(foreground.contrast(with: selectedTab), 4.5 - 0.00001)
                            let graphFill = surface.mixed(with: foreground, amount: 0.23)
                            XCTAssertGreaterThanOrEqual(foreground.contrast(with: graphFill), 3 - 0.00001)
                        }
                    }
                }
            }
        }
    }

    func testReadableColorPreservesTheStoredAndPickerColor() throws {
        let black = UsageAccent.custom(red: 0, green: 0, blue: 0)
        let data = try JSONEncoder().encode(black)
        let raw = RGB(NSColor(black.color(scheme: .dark)))
        let readable = RGB(NSColor(black.readableColor(scheme: .dark)))
        XCTAssertEqual(raw, RGB(red: 0, green: 0, blue: 0))
        XCTAssertGreaterThan(readable.luminance, 0.2)
        XCTAssertEqual(RGB(NSColor(UsageChartStyle.accent(for: 68, scheme: .dark, selection: black))), readable)
        XCTAssertEqual(RGB(NSColor(UsageChartStyle.surfaceTint(for: 68, scheme: .dark, selection: black))), raw)
        XCTAssertEqual(try JSONDecoder().decode(UsageAccent.self, from: data), black)

        let white = UsageAccent.custom(red: 1, green: 1, blue: 1)
        XCTAssertLessThan(RGB(NSColor(white.readableColor(scheme: .light))).luminance, 0.2)
        XCTAssertEqual(RGB(NSColor(white.color(scheme: .light))), RGB(red: 1, green: 1, blue: 1))
    }

    func testAlreadyReadableColorIsUnchanged() {
        let tint = RGB(red: 0.57, green: 0.94, blue: 0.79)
        XCTAssertEqual(AccentContrast.foreground(tint, background: RGB(red: 0.12, green: 0.12, blue: 0.12), dark: true), tint)
    }
}
