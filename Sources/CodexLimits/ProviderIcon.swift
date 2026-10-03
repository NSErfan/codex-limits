import AppKit
import CodexWidgetKit
import SwiftUI

@MainActor
struct ProviderIcon: View {
    let provider: UsageProvider
    var size: CGFloat = 18

    private static let resourceBundle: Bundle = {
        // Prefer the installed app's Resources bundle over SwiftPM's build-directory fallback.
        if let url = Bundle.main.url(forResource: "CodexLimits_CodexLimits", withExtension: "bundle"),
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

    var body: some View {
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

    static func image(for provider: UsageProvider) -> NSImage? {
        images[provider]
    }
}
