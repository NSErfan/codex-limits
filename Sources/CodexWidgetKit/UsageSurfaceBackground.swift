import SwiftUI

public struct UsageSurfaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.usageAccent) private var usageAccent
    private let remaining: Double?

    public init(remaining: Double?) {
        self.remaining = remaining
    }

    public var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
            LinearGradient(
                colors: [accent.opacity(scheme == .dark ? 0.13 : 0.08), .clear],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [accent.opacity(scheme == .dark ? 0.12 : 0.05), .clear],
                center: .bottomTrailing, startRadius: 0, endRadius: 220
            )
        }
    }

    private var accent: Color { UsageChartStyle.surfaceTint(for: remaining, scheme: scheme, selection: usageAccent) }
}
