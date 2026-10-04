import AppKit
import SwiftUI

@MainActor
public struct ProviderIcon: View {
    let provider: UsageProvider
    let size: CGFloat

    public init(provider: UsageProvider, size: CGFloat = 18) {
        self.provider = provider
        self.size = size
    }

    private static let resourceBundle: Bundle = {
        // Load from the app or extension's own Resources before SwiftPM's build-directory fallback.
        if let url = Bundle.main.url(forResource: "CodexLimits_CodexWidgetKit", withExtension: "bundle"),
           let bundle = Bundle(url: url) {
            return bundle
        }
        return .module
    }()

    private static let images: [UsageProvider: NSImage] = Dictionary(uniqueKeysWithValues:
        UsageProvider.allCases.compactMap { provider in
            guard let url = resourceBundle.url(forResource: "ProviderIcon-\(provider.rawValue)", withExtension: "pdf"),
                  let image = NSImage(contentsOf: url) else { return nil }
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            return (provider, image)
        }
    )

    public var body: some View {
        Group {
            if let image = Self.image(for: provider) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "terminal")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    public static func image(for provider: UsageProvider) -> NSImage? {
        images[provider]
    }
}
