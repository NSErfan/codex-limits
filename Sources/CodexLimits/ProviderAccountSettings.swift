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
                    Text(accountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
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
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = monitor.refreshMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let snapshot = monitor.snapshot {
                Text("Last reading: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let message = login.message(for: monitor.provider) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if monitor.requiresLogin {
                Link("Install \(monitor.provider.cliDisplayName)", destination: ProviderLogin.installationURL(for: monitor.provider))
                    .font(.caption)
            }
        }
    }

    private var accountDescription: String {
        guard let snapshot = monitor.snapshot else { return "Account not loaded" }
        guard let account = snapshot.accountName else { return "Account name unavailable" }
        return monitor.requiresLogin ? "Last account: \(account)" : account
    }

    private var status: String {
        if monitor.isRefreshing { return "Checking usage…" }
        if monitor.requiresLogin { return "Sign-in needed" }
        if monitor.snapshot != nil {
            return monitor.errorMessage == nil && monitor.refreshMessage == nil
                ? "Usage available" : "Showing last usage reading"
        }
        return "Usage unavailable"
    }
}
