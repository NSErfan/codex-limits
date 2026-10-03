import SwiftUI

struct ProviderMenuLabel: View {
    @ObservedObject var monitor: UsageMonitor
    var displayMode: MenuBarDisplayMode = .iconOnly

    var body: some View {
        HStack(spacing: 4) {
            if displayMode != .textOnly {
                ProviderIcon(provider: monitor.provider)
            }
            if displayMode != .iconOnly {
                Text("\(monitor.provider.displayName) \(monitor.menuBarText)")
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(usageDescription)
        .help(usageDescription)
    }

    private var usageDescription: String {
        monitor.snapshot == nil
            ? "\(monitor.provider.displayName): usage unavailable"
            : "\(monitor.provider.displayName): \(monitor.menuBarText) remaining"
    }
}
