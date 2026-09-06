import SwiftUI

struct ModelActivityWindow: View {
    @ObservedObject var monitor: UsageMonitor

    var body: some View {
        ModelActivityView(samples: monitor.samples, window: monitor.snapshot?.mainLimit.window)
            .background(ModelActivityAppPresence().frame(width: 0, height: 0))
    }
}
