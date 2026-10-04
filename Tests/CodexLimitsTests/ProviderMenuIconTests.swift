import AppKit
import CodexWidgetKit
import XCTest
@testable import CodexLimits

@MainActor
final class ProviderMenuIconTests: XCTestCase {
    func testMenuIconsReserveTransparentSpaceAfterArtwork() throws {
        for provider in UsageProvider.allCases {
            let image = try XCTUnwrap(ProviderMenuIcon.image(for: provider))
            XCTAssertTrue(image.isTemplate, "\(provider) must follow the menu bar's appearance")
            XCTAssertEqual(image.size, NSSize(width: 25, height: 18))

            let bitmap = try renderAtDoubleScale(image)
            let artwork = alphaMask(in: bitmap, columns: 0 ..< 36)
            let spacing = alphaMask(in: bitmap, columns: 36 ..< 50)
            XCTAssertTrue(artwork.contains { $0 > 0.9 }, "\(provider) must retain visible artwork")
            XCTAssertTrue(spacing.allSatisfy { $0 == 0 }, "\(provider) must leave seven points clear after the icon")
        }
    }

    func testPaddingPreservesOriginalArtworkAndSourceImage() throws {
        for provider in UsageProvider.allCases {
            let source = try XCTUnwrap(ProviderIcon.image(for: provider))
            let originalMask = alphaMask(in: try renderAtDoubleScale(source), columns: 0 ..< 36)
            let image = try XCTUnwrap(ProviderMenuIcon.image(for: provider))
            let paddedMask = alphaMask(in: try renderAtDoubleScale(image), columns: 0 ..< 36)

            XCTAssertEqual(paddedMask.count, originalMask.count)
            let largestDifference = zip(paddedMask, originalMask).map { abs($0 - $1) }.max() ?? 0
            XCTAssertLessThanOrEqual(largestDifference, 1.0 / 255.0,
                                     "\(provider) must keep the original icon's shape, size, and position")
            XCTAssertEqual(source.size, NSSize(width: 18, height: 18))
            XCTAssertEqual(alphaMask(in: try renderAtDoubleScale(source), columns: 0 ..< 36), originalMask,
                           "\(provider) must not change the shared icon used outside the menu bar")
        }
    }

    private func renderAtDoubleScale(_ image: NSImage) throws -> NSBitmapImageRep {
        let width = Int(image.size.width * 2)
        let height = Int(image.size.height * 2)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                  isPlanar: false, colorSpaceName: .deviceRGB,
                                                  bytesPerRow: 0, bitsPerPixel: 0))
        let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        context.cgContext.clear(bounds)
        image.draw(in: bounds)
        return bitmap
    }

    private func alphaMask(in bitmap: NSBitmapImageRep, columns: Range<Int>) -> [CGFloat] {
        (0 ..< bitmap.pixelsHigh).flatMap { y in
            columns.map { x in bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        }
    }
}
