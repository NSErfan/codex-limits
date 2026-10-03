import SwiftUI

struct ProviderMenuLabel: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text("\(monitor.provider.displayName) \(monitor.menuBarText)")
                .monospacedDigit()
        }
        .accessibilityLabel("\(monitor.provider.displayName): \(monitor.menuBarText) remaining")
    }
}
