import AppKit
import CodexWidgetKit

@MainActor
enum ProviderMenuIcon {
    private static let images: [UsageProvider: NSImage] = Dictionary(uniqueKeysWithValues:
        UsageProvider.allCases.compactMap { provider in
            guard let source = ProviderIcon.image(for: provider)
                ?? NSImage(systemSymbolName: "terminal", accessibilityDescription: nil) else { return nil }
            return (provider, paddedImage(source))
        }
    )

    static func image(for provider: UsageProvider) -> NSImage? {
        images[provider]
    }

    private static func paddedImage(_ source: NSImage) -> NSImage {
        // MenuBarExtra ignores SwiftUI padding. Keep the gap in the native image's canvas.
        let image = NSImage(size: NSSize(width: 25, height: 18), flipped: false) { _ in
            source.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
            return true
        }
        image.isTemplate = true
        return image
    }
}
