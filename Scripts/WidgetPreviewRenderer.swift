import AppKit
import CodexWidgetKit
import SwiftUI

/// Renders the production SwiftUI views with synthetic data for visual QA.
@main
enum WidgetPreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let provider = CommandLine.arguments.dropFirst(2).first.flatMap(UsageProvider.init(rawValue:)) ?? .codex
        let prefix = provider == .codex ? "" : "\(provider.rawValue)-"
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WeeklyWidgetSnapshot.preview(at: now)
        let sheet = VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(provider.displayName.uppercased()) / WIDGETS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Text("A little clarity. All week long.")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .tracking(-0.6)
                Text("Two ways to keep your weekly limit in sight.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            row(snapshot: snapshot, date: now, scheme: .dark, provider: provider)
            row(snapshot: snapshot, date: now, scheme: .light, provider: provider)
            HStack {
                Text("01  Weekly percentage").frame(width: 170, alignment: .leading)
                Text("02  Weekly graph").frame(width: 364, alignment: .leading)
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            Text("SWIFTUI RENDER · SYNTHETIC PREVIEW DATA")
                .font(.system(size: 8, design: .monospaced)).tracking(1.5).foregroundStyle(.tertiary)
        }
        .padding(36)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        try render(sheet, to: directory.appendingPathComponent("\(prefix)weekly-widgets.png"))
        let paces = VStack(alignment: .leading, spacing: 20) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                ForEach([WeeklyPace.onTrack, .slowDown, .roomToUseMore], id: \.rawValue) { pace in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(pace.title).font(.headline)
                        row(snapshot: .preview(at: now, pace: pace), date: now, scheme: scheme, provider: provider)
                    }
                }
            }
        }
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
        try render(paces, to: directory.appendingPathComponent("\(prefix)weekly-widget-paces.png"))
        let states = VStack(alignment: .leading, spacing: 20) {
            ForEach([100.0, 25, 8, 0], id: \.self) { remaining in
                row(snapshot: .preview(at: now, remaining: remaining), date: now, scheme: .dark, provider: provider)
            }
            row(snapshot: snapshot, date: now.addingTimeInterval(2_000), scheme: .dark, provider: provider)
            row(snapshot: snapshot, date: now.addingTimeInterval(5 * 86_400), scheme: .dark, provider: provider)
            row(snapshot: nil, date: now, scheme: .light, provider: provider)
        }
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        try render(states, to: directory.appendingPathComponent("\(prefix)weekly-widget-states.png"))
    }

    @MainActor private static func row(
        snapshot: WeeklyWidgetSnapshot?, date: Date, scheme: ColorScheme, provider: UsageProvider
    ) -> some View {
        HStack(spacing: 24) {
            WeeklyPercentageView(snapshot: snapshot, date: date, provider: provider)
                .frame(width: 170, height: 170)
                .background { UsageSurfaceBackground(remaining: snapshot?.window?.remainingPercent) }
                .clipShape(RoundedRectangle(cornerRadius: 23))
            WeeklyGraphView(snapshot: snapshot, date: date, provider: provider)
                .frame(width: 364, height: 170)
                .background { UsageSurfaceBackground(remaining: snapshot?.window?.remainingPercent) }
                .clipShape(RoundedRectangle(cornerRadius: 23))
        }
        .environment(\.colorScheme, scheme)
    }

    @MainActor private static func render<Content: View>(_ content: Content, to url: URL) throws {
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw NSError(domain: "WidgetPreviewRenderer", code: 1)
        }
        try png.write(to: url)
        print(url.path)
    }
}
