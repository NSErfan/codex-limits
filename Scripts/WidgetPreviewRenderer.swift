import AppKit
import CodexWidgetKit
import SwiftUI

/// Renders the production SwiftUI views with synthetic data for visual QA.
@main
enum WidgetPreviewRenderer {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = WeeklyWidgetSnapshot.preview(at: now)
        let sheet = VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text("CODEX LIMITS / WIDGETS")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Text("A little clarity. All week long.")
                    .font(.system(size: 30, weight: .medium, design: .rounded))
                    .tracking(-0.6)
                Text("Two ways to keep your weekly limit in sight.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            row(snapshot: snapshot, date: now, scheme: .dark)
            row(snapshot: snapshot, date: now, scheme: .light)
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
        try render(sheet, to: directory.appendingPathComponent("weekly-widgets.png"))
        let states = VStack(alignment: .leading, spacing: 20) {
            ForEach([100.0, 25, 8, 0], id: \.self) { remaining in
                row(snapshot: .preview(at: now, remaining: remaining), date: now, scheme: .dark)
            }
            row(snapshot: snapshot, date: now.addingTimeInterval(2_000), scheme: .dark)
            row(snapshot: snapshot, date: now.addingTimeInterval(5 * 86_400), scheme: .dark)
            row(snapshot: nil, date: now, scheme: .light)
        }
        .padding(30)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        try render(states, to: directory.appendingPathComponent("weekly-widget-states.png"))
    }

    @MainActor private static func row(snapshot: WeeklyWidgetSnapshot?, date: Date, scheme: ColorScheme) -> some View {
        HStack(spacing: 24) {
            WeeklyPercentageView(snapshot: snapshot, date: date)
                .frame(width: 170, height: 170)
                .background { WeeklyWidgetBackground(remaining: snapshot?.window?.remainingPercent) }
                .clipShape(RoundedRectangle(cornerRadius: 23))
            WeeklyGraphView(snapshot: snapshot, date: date)
                .frame(width: 364, height: 170)
                .background { WeeklyWidgetBackground(remaining: snapshot?.window?.remainingPercent) }
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
