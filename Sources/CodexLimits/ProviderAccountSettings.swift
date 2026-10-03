import CodexWidgetKit
import SwiftUI

struct ProviderAccountSettings: View {
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var login: ProviderLoginSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.provider.displayName).fontWeight(.medium)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await login.refresh(monitor.provider) }
                }
                .disabled(monitor.isRefreshing)
                Button("Sign in…") { login.signIn(to: monitor.provider) }
                    .disabled(login.isOpening(monitor.provider))
            }
            if let error = monitor.errorMessage {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
            if let message = login.message(for: monitor.provider) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if monitor.requiresLogin {
                Link("Install \(monitor.provider.displayName) CLI", destination: ProviderLogin.installationURL(for: monitor.provider))
                    .font(.caption)
            }
        }
    }

    private var status: String {
        if monitor.isRefreshing { return "Checking usage…" }
        if monitor.requiresLogin { return "Sign-in needed" }
        if monitor.snapshot != nil, monitor.errorMessage == nil { return "Usage available" }
        return "Usage unavailable"
    }
}
