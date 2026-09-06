import AppKit
import SwiftUI

@main
struct ModelActivityPreview: App {
    private let store: ModelActivityStore
    private let samples: [UsageSample]

    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        let now = Date()
        let events = (0 ..< 400).map { index in
            let model = ["gpt-6-astra", "gpt-5.6-sol", "gpt-5.6-luna"][index % 3]
            let effort = ["high", "medium", "low"][(index / 3) % 3]
            let total = Int64(2_000 + (index % 17) * 450)
            return ModelActivityEvent(id: "preview-\(index)", date: now.addingTimeInterval(-Double(index < 18 ? index * 2 + 1 : index * 1_400 + 60)),
                                      group: .init(model: model, effort: effort),
                                      tokens: .init(input: total - 500, output: 500, cached: 1_000, total: total))
        }
        samples = (0 ... 336).compactMap { index in
            guard !(190 ... 205).contains(index) else { return nil }
            return UsageSample(observedAt: now.addingTimeInterval(Double(index - 336) * 1_800),
                               remainingPercent: 100 - Double(index) / 336 * 65,
                               resetsAt: now.addingTimeInterval(2 * 86_400))
        }
        store = ModelActivityStore(previewEvents: events, now: now)
        store.updateHistory(samples)
    }

    var body: some Scene {
        WindowGroup("Model Activity — Synthetic Preview") {
            ModelActivityView(store: store, loadsAutomatically: false, samples: samples,
                              window: UsageWindow(remainingPercent: 35, resetsAt: samples.last!.resetsAt, durationMinutes: 10_080))
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
        }
        .defaultSize(width: 1_080, height: 880)
    }
}
