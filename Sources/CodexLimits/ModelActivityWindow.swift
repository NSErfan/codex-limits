import SwiftUI

struct ModelActivityWindow: View {
    @ObservedObject var monitor: UsageMonitor
    /// The window closes when its provider is turned off.
    var isProviderEnabled = true
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        ModelActivityView(samples: monitor.samples, window: monitor.snapshot?.mainLimit.window)
            .background(ModelActivityAppPresence().frame(width: 0, height: 0))
            .onChange(of: isProviderEnabled, initial: true) { _, isEnabled in
                if !isEnabled { dismissWindow(id: "model-activity") }
            }
    }
}
