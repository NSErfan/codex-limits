import SwiftUI

struct ProviderMenuLabel: View {
    @ObservedObject var monitor: UsageMonitor
    var displayMode: MenuBarDisplayMode = .iconOnly
    var usageWindow: MenuBarUsageWindow = .automatic

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
            ? menuBarText
            : "\(monitor.provider.displayName) \(menuBarText)"
    }

    private var limit: LimitReading? {
        usageWindow.limit(in: monitor.snapshot, provider: monitor.provider)
    }

    private var menuBarText: String {
        let percentage = UsageMonitor.menuBarText(remainingPercent: limit?.window.remainingPercent)
        return showsFixedWindow ? "\(usageWindow.shortTitle) \(percentage)" : percentage
    }

    private var showsFixedWindow: Bool {
        usageWindow != .automatic && MenuBarUsageWindow.options(for: monitor.provider).contains(usageWindow)
    }

    private var usageDescription: String {
        let windowName = showsFixedWindow ? "\(usageWindow.title) " : ""
        let percentage = UsageMonitor.menuBarText(remainingPercent: limit?.window.remainingPercent)
        let status = limit == nil ? "usage unavailable" : "\(percentage) remaining"
        return "\(monitor.provider.displayName): \(windowName)\(status)"
    }
}
