import SwiftUI

struct ModelActivityWindow: View {
    let profile: CodexProfile
    @ObservedObject var monitor: UsageMonitor
    let isAccountEnabled: Bool
    @Environment(\.dismissWindow) private var dismissWindow

    static func sceneID(for profile: CodexProfile) -> String {
        profile == .secondary ? "model-activity-codex-2" : "model-activity"
    }

    static func title(for profile: CodexProfile) -> String {
        profile == .secondary ? "Model activity · Codex 2" : "Model activity · Codex"
    }

    var body: some View {
        content
            .background(ModelActivityAppPresence().frame(width: 0, height: 0))
            .onChange(of: isAccountEnabled, initial: true) { _, isEnabled in
                if !isEnabled { dismissWindow(id: Self.sceneID(for: profile)) }
            }
    }

    @ViewBuilder private var content: some View {
        if profile == .secondary, (try? CodexProfile.validateSecondaryHome()) == nil {
            ContentUnavailableView(
                "Codex 2 profile unavailable",
                systemImage: "exclamationmark.triangle",
                description: Text(CodexClientError.profileAlreadyInUse.localizedDescription)
            )
        } else {
            ModelActivityView(
                home: profile.home(), title: Self.title(for: profile),
                samples: monitor.samples, window: monitor.snapshot?.mainLimit.window
            )
        }
    }
}
