import CodexWidgetKit
import SwiftUI

struct WidgetGalleryView: View {
    @ObservedObject var monitor: UsageMonitor
    @Environment(\.usageAccent) private var usageAccent
    @State private var appearance = Appearance.dark
    private enum Appearance: String, CaseIterable { case light = "Light", dark = "Dark" }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let snapshot = previewSnapshot
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little clarity.\nAll week long.")
                            .font(.system(size: 32, weight: .medium, design: .rounded))
                            .tracking(-0.8)
                        Text("Your Codex limit, right where you work.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 130)
                }
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 12) {
                        card(width: 170, remaining: snapshot.window?.remainingPercent) {
                            WeeklyPercentageView(snapshot: snapshot, date: context.date)
                        }
                        description("01", title: "Just the number", subtitle: "Weekly percentage · Small")
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        card(width: 364, remaining: snapshot.window?.remainingPercent) {
                            WeeklyGraphView(snapshot: snapshot, date: context.date)
                        }
                        description("02", title: "The bigger picture", subtitle: "Weekly graph · Medium")
                    }
                }
                Divider()
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Make room on your desktop")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Control-click the desktop → Edit Widgets → Codex Limits.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        if Bundle.main.object(forInfoDictionaryKey: "CodexWidgetAppGroup") == nil {
                            Text("This local build previews both designs. Desktop data sharing requires a developer-signed build; see the README.")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Text(monitor.snapshot == nil ? "SAMPLE DATA" : "YOUR USAGE")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.primary.opacity(0.05), in: Capsule())
                }
            }
            .padding(32)
            .frame(width: 622)
        }
        .preferredColorScheme(appearance == .dark ? .dark : .light)
        .tint(usageAccent.readableColor(scheme: appearance == .dark ? .dark : .light))
    }

    private var previewSnapshot: WeeklyWidgetSnapshot {
        guard let usage = monitor.snapshot else { return .preview() }
        let current = WeeklyWidgetPublisher.snapshot(from: usage)
        if let shared = monitor.weeklyWidgetSnapshot {
            return (shared.fetchedAt > current.fetchedAt ? shared : current).merging([shared, current])
        }
        return current
    }

    private func card<Content: View>(width: CGFloat, remaining: Double?, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(width: width, height: 170)
            .background { UsageSurfaceBackground(remaining: remaining) }
            .clipShape(RoundedRectangle(cornerRadius: 23, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 23, style: .continuous)
                    .strokeBorder(.primary.opacity(0.09), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.12), radius: 15, y: 8)
    }

    private func description(_ number: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Text(number).font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            Text(subtitle).font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
