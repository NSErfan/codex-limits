import SwiftUI

struct ProviderMenuLabel: View {
    @ObservedObject var monitor: UsageMonitor
    var displayMode: MenuBarDisplayMode = .iconOnly

    var body: some View {
        HStack(spacing: 2) {
            if displayMode != .textOnly {
                if let image = ProviderMenuIcon.image(for: monitor.provider) {
                    Image(nsImage: image)
                        .accessibilityHidden(true)
                }
            }
            // MenuBarExtra uses one native title; separate Text views can lose the percentage.
            Text(title)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usageDescription)
        .help(usageDescription)
    }

    private var title: String {
        displayMode == .iconOnly
            ? monitor.menuBarText
            : "\(monitor.provider.displayName) \(monitor.menuBarText)"
    }

    private var usageDescription: String {
        monitor.snapshot == nil
            ? "\(monitor.provider.displayName): usage unavailable"
            : "\(monitor.provider.displayName): \(monitor.menuBarText) remaining"
    }
}
