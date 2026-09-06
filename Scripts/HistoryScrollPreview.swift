import AppKit
import CodexWidgetKit
import SwiftUI

/// A regular window for reproducible scroll QA with the production chart.
@main
struct HistoryScrollPreview: App {
    private let now = Date(timeIntervalSince1970: 1_789_000_000)

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup("History Scroll Preview") {
            VStack(alignment: .leading, spacing: 16) {
                Text("7-DAY SCROLL · 30 DAYS OF SAMPLE DATA")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                HistoryChart(
                    samples: samples, range: now.addingTimeInterval(-30 * 86_400) ... now,
                    bucketDuration: 1_800, visibleDuration: 7 * 86_400, remainingPercent: 65
                )
            }
            .padding(24).frame(width: 460)
            .background { UsageSurfaceBackground(remaining: 65) }
            .environment(\.colorScheme, .dark)
            .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .windowResizability(.contentSize)
    }

    private var samples: [UsageSample] {
        (0 ... 4_320).compactMap { index in
            // Plateau-heavy readings, weekly resets, and one collection gap.
            guard !(2_000 ... 2_048).contains(index) else { return nil }
            let date = now.addingTimeInterval(Double(index - 4_320) * 600)
            let cycleIndex = index % 1_008
            return UsageSample(
                observedAt: date,
                remainingPercent: max(0, 100 - Double(cycleIndex / 12)),
                resetsAt: date.addingTimeInterval(Double(1_008 - cycleIndex) * 600)
            )
        }
    }
}
