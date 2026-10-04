import AppKit
import XCTest
@testable import CodexWidgetKit

@MainActor
final class ProviderIconTests: XCTestCase {
    func testBundledIconsRenderAsTransparentTemplates() throws {
        for provider in UsageProvider.allCases {
            let image = try XCTUnwrap(ProviderIcon.image(for: provider))
            XCTAssertTrue(image.isTemplate)
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            let mask = try alphaMask(of: image)
            XCTAssertTrue(mask.contains { $0 > 0.9 }, "\(provider) must have visible artwork")
            XCTAssertTrue(mask.contains { $0 < 0.1 }, "\(provider) must retain its transparent background")
        }
    }

    func testProvidersHaveDifferentArtwork() throws {
        let codex = try XCTUnwrap(ProviderIcon.image(for: .codex))
        let claude = try XCTUnwrap(ProviderIcon.image(for: .claude))
        XCTAssertNotEqual(try alphaMask(of: codex), try alphaMask(of: claude))
    }

    private func alphaMask(of image: NSImage) throws -> [CGFloat] {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 36, height: 36))
        image.draw(in: NSRect(x: 0, y: 0, width: 36, height: 36))
        return (0 ..< 36).flatMap { y in
            (0 ..< 36).map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        }
    }
}
