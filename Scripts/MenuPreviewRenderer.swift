import AppKit
import CodexWidgetKit
import SwiftUI

/// Visual QA uses synthetic state unless a real activity history directory is explicitly supplied.
@main
enum MenuPreviewRenderer {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()
        let suite = "MenuPreviewRenderer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: temporary)
        }
        let weekly = WeeklyWidgetSnapshot.preview(at: now)
        let window = UsageWindow(remainingPercent: 68, resetsAt: weekly.window!.resetsAt, durationMinutes: 10_080)
        let snapshot = UsageSnapshot(
            mainLimit: .init(limitId: "codex", name: "Codex", window: window),
            otherLimits: [.init(limitId: "codex", name: "5-hour limit", window: .init(remainingPercent: 92, resetsAt: now.addingTimeInterval(9_000), durationMinutes: 300))],
            tokenHistory: [],
            resetCredits: [.init(id: "sample-reset", title: "Banked reset", expiresAt: now.addingTimeInterval(2 * 86_400))],
            fetchedAt: now
        )
        let samples = (0 ... 1_440).map { index in
            let date = now.addingTimeInterval(Double(index - 1_440) * 1_800)
            let elapsed = date.timeIntervalSince(window.startsAt)
            let cycle = floor(elapsed / (7 * 86_400))
            let cycleStart = window.startsAt.addingTimeInterval(cycle * 7 * 86_400)
            let days = date.timeIntervalSince(cycleStart) / 86_400
            let remaining = max(0, 100 - days * (cycle == 0 ? 32.0 / 3 : 13))
            return UsageSample(observedAt: date, remainingPercent: remaining, resetsAt: cycleStart.addingTimeInterval(7 * 86_400))
        }.filter { sample in
            // Collection gaps check continuous connections and the muted fill.
            let age = now.timeIntervalSince(sample.observedAt)
            let hours = age / 3_600
            let longGap = (240.0 ... 248.0).contains(hours)
            let recentGap = (48.0 ... 60.0).contains(hours)
            let isolatedReadings = (96.0 ... 120.0).contains(hours)
                && Int(age / 1_800) % 4 != 0
            return !longGap && !recentGap && !isolatedReadings
        }
        defaults.set(try JSONEncoder().encode(State(snapshot: snapshot, samples: samples, previousStatus: nil)), forKey: "usageState")
        let monitor = UsageMonitor(
            defaults: defaults, historyDirectory: temporary,
            widgetStore: WeeklyWidgetStore(directory: temporary.appendingPathComponent("widget")),
            fetchUsage: { snapshot },
            startsAutomatically: false
        )
        let menus = HStack(alignment: .top, spacing: 24) {
            menu(monitor: monitor, defaults: defaults, scheme: .dark)
            menu(monitor: monitor, defaults: defaults, scheme: .light)
        }
        .padding(24)
        .background(Color.gray.opacity(0.15))
        try render(menus, to: output.appendingPathComponent("menu-window.png"))

        let comparison = VStack(alignment: .leading, spacing: 24) {
            Text("CODEX LIMITS · ONE VISUAL LANGUAGE")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .tracking(2).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                menu(monitor: monitor, defaults: defaults, scheme: .dark)
                VStack(alignment: .leading, spacing: 24) {
                    WeeklyGraphView(snapshot: weekly, date: now)
                        .frame(width: 364, height: 170)
                        .background { UsageSurfaceBackground(remaining: 68) }
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                    WeeklyPercentageView(snapshot: weekly, date: now)
                        .frame(width: 170, height: 170)
                        .background { UsageSurfaceBackground(remaining: 68) }
                        .clipShape(RoundedRectangle(cornerRadius: 23))
                    Text("SYNTHETIC PREVIEW DATA")
                        .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(28)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, .dark)
        try render(comparison, to: output.appendingPathComponent("menu-and-widgets.png"))
        try render(comparison.environment(\.usageAccent, .blue), to: output.appendingPathComponent("accent-blue.png"))
        try render(menus.environment(\.usageAccent, .rose), to: output.appendingPathComponent("accent-rose.png"))
        let black = UsageAccent.custom(red: 0, green: 0, blue: 0)
        let white = UsageAccent.custom(red: 1, green: 1, blue: 1)
        let navy = UsageAccent.custom(red: 0.01, green: 0.02, blue: 0.08)
        try render(comparison.environment(\.usageAccent, black), to: output.appendingPathComponent("accent-black-widgets.png"))
        try render(menus.environment(\.usageAccent, black), to: output.appendingPathComponent("accent-black.png"))
        try render(menus.environment(\.usageAccent, white), to: output.appendingPathComponent("accent-white.png"))
        try render(menus.environment(\.usageAccent, navy), to: output.appendingPathComponent("accent-navy.png"))

        let appearance = AppearanceSettings(defaults: defaults, widgetStore: nil)
        appearance.setAccent(.blue)
        let settingsPreview = HStack(alignment: .top, spacing: 24) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                SettingsView(monitor: monitor, appearance: appearance)
                    .defaultAppStorage(defaults)
                    .frame(height: 720)
                    .environment(\.colorScheme, scheme)
            }
        }
        .padding(24).background(Color.gray.opacity(0.15))
        try render(settingsPreview, to: output.appendingPathComponent("accent-settings.png"))

        let activityEvents = (0 ..< 400).map { index in
            let model = ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna"][index % 3]
            let effort = ["high", "medium", "low"][(index / 3) % 3]
            let total = Int64(2_000 + (index % 17) * 450)
            return ModelActivityEvent(id: "preview-\(index)", date: now.addingTimeInterval(-Double(index < 18 ? index * 2 + 1 : index * 1_400 + 60)),
                                      group: .init(model: model, effort: effort),
                                      tokens: .init(input: total - 500, output: 500, cached: 1_000, total: total))
        }
        let activityStore = ModelActivityStore(previewEvents: activityEvents, now: now)
        activityStore.selectedModels = ["gpt-6-astra"]
        activityStore.updateHistory(samples)
        var activitySamples = samples
        if let path = ProcessInfo.processInfo.environment["PREVIEW_ACTIVITY_HISTORY"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("installations")
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            let files = enumerator.allObjects
            var recordedSamples: [UsageSample] = []
            for case let file as URL in files where file.pathExtension == "json" && !file.lastPathComponent.hasPrefix(".") {
                let daily = try JSONDecoder().decode(ActivityHistoryDay.self, from: Data(contentsOf: file))
                recordedSamples.append(contentsOf: daily.samples)
            }
            await activityStore.refresh()
            guard activityStore.lastUpdated != nil, !recordedSamples.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            activitySamples = UsageMonitor.mergedSamples([], recordedSamples)
            activityStore.updateHistory(activitySamples)
        }
        let activityPreview = ModelActivityView(store: activityStore, loadsAutomatically: false, samples: activitySamples)
            .frame(width: 1_080, height: 1_140)
        try render(activityPreview.environment(\.colorScheme, .dark), to: output.appendingPathComponent("model-activity-dark.png"))
        try render(activityPreview.environment(\.colorScheme, .light), to: output.appendingPathComponent("model-activity-light.png"))

        let exampleStore = ModelActivityStore(previewEvents: activityEvents, now: now)
        if let interval = exampleStore.timeline.interval(at: nil) {
            for scheme in [ColorScheme.dark, .light] {
                let pies = ModelActivityPieCharts(interval: interval, metric: .total, selectedModel: .constant("gpt-6-astra"))
                    .padding(26).frame(width: 780)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.12) : Color.white)
                try render(pies, to: output.appendingPathComponent("model-pies-\(scheme == .dark ? "dark" : "light").png"))
            }
        }

        let detailStyles = HStack(alignment: .top, spacing: 24) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                VStack(spacing: 14) {
                    PaceStatusView(status: .slowDown, message: "At this pace, your limit may run out 5 days before the reset.", color: UsageChartStyle.accent(for: 0, scheme: scheme))
                    PaceStatusView(status: .onTrack, message: "You’re on track to have 15% left at the reset.", color: UsageChartStyle.accent(for: 100, scheme: scheme))
                    ChartHoverReadout(title: "97% remaining", detail: "Sep 6, 2026 at 5:52 AM")
                    ChartHoverReadout(title: "Reset", detail: "Sep 13 at 5:52 AM", symbol: "arrow.counterclockwise")
                    ChartHoverReadout(title: "≈72% remaining", detail: "Sep 6 at 5:52 AM", hint: "Estimated · No sample here")
                    ChartHoverReadout(title: "Banked reset", detail: "Expires Sep 21 at 8:14 AM", symbol: "arrow.counterclockwise", hint: "Click to pace to this reset")
                }
                .padding(20).frame(width: 460)
                .background { UsageSurfaceBackground(remaining: 68) }
                .environment(\.colorScheme, scheme)
                .clipShape(RoundedRectangle(cornerRadius: 23))
            }
        }
        .padding(24).background(Color.gray.opacity(0.15))
        try render(detailStyles, to: output.appendingPathComponent("menu-detail-styles.png"))

        let history = HStack(alignment: .top, spacing: 24) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                VStack(alignment: .leading, spacing: 16) {
                    Text("30-DAY HISTORY").font(.system(size: 11, weight: .medium, design: .monospaced))
                    HistoryChart(samples: samples, range: now.addingTimeInterval(-30 * 86_400) ... now, bucketDuration: 1_800, visibleDuration: nil, remainingPercent: 68)
                }
                .padding(20).frame(width: 460)
                .background { UsageSurfaceBackground(remaining: 68) }
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .environment(\.colorScheme, scheme)
            }
        }
        .padding(24).background(Color.gray.opacity(0.15))
        try render(history, to: output.appendingPathComponent("menu-history.png"))

        let recentHistory = HStack(alignment: .top, spacing: 24) {
            ForEach([ColorScheme.dark, .light], id: \.self) { scheme in
                VStack(alignment: .leading, spacing: 16) {
                    Text("7-DAY HISTORY · SAMPLING GAPS").font(.system(size: 11, weight: .medium, design: .monospaced))
                    HistoryChart(samples: samples, range: now.addingTimeInterval(-7 * 86_400) ... now, bucketDuration: 1_800, visibleDuration: 7 * 86_400, remainingPercent: 68)
                }
                .padding(20).frame(width: 460)
                .background { UsageSurfaceBackground(remaining: 68) }
                .clipShape(RoundedRectangle(cornerRadius: 23))
                .environment(\.colorScheme, scheme)
            }
        }
        .padding(24).background(Color.gray.opacity(0.15))
        try render(recentHistory, to: output.appendingPathComponent("menu-history-gaps.png"))
        try render(recentHistory.environment(\.usageAccent, black), to: output.appendingPathComponent("accent-black-history.png"))
    }

    private struct ActivityHistoryDay: Decodable {
        let samples: [UsageSample]
    }

    @MainActor private static func menu(monitor: UsageMonitor, defaults: UserDefaults, scheme: ColorScheme) -> some View {
        MenuContentView(monitor: monitor)
            .defaultAppStorage(defaults)
            .environment(\.colorScheme, scheme)
            .clipShape(RoundedRectangle(cornerRadius: 23))
    }

    @MainActor private static func render<Content: View>(_ view: Content, to url: URL) throws {
        // ImageRenderer substitutes warning symbols for AppKit-backed menus and
        // buttons. Host the real view offscreen so those controls render too.
        let hosting = NSHostingView(rootView: view)
        let size = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: size.width, height: size.height), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw NSError(domain: "MenuPreviewRenderer", code: 1)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        window.orderOut(nil)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "MenuPreviewRenderer", code: 2)
        }
        try data.write(to: url)
        print(url.path)
    }

    private struct State: Encodable {
        let snapshot: UsageSnapshot
        let samples: [UsageSample]
        let previousStatus: PaceStatus?
    }
}
