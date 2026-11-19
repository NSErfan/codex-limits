import CodexWidgetKit
import SwiftUI

struct ProviderAccountSettings: View {
    @ObservedObject var monitor: UsageMonitor
    @ObservedObject var login: ProviderLoginSession
    var moveEarlier: (() -> Void)?
    var moveLater: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if moveEarlier != nil || moveLater != nil {
                    VStack(spacing: 2) {
                        orderButton("Move \(monitor.account.displayName) up", symbol: "chevron.up", action: moveEarlier)
                        orderButton("Move \(monitor.account.displayName) down", symbol: "chevron.down", action: moveLater)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.account.displayName).fontWeight(.medium)
                    Text(accountDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh") {
                    Task { await login.refresh(monitor.account) }
                }
                .disabled(monitor.isRefreshing)
                Button("Sign in…") { login.signIn(to: monitor.account) }
                    .disabled(login.isOpening(monitor.account))
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
            if let message = login.message(for: monitor.account) {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
            if monitor.requiresInstallation {
                Link("Install \(monitor.provider.cliDisplayName)", destination: ProviderLogin.installationURL(for: monitor.provider))
                    .font(.caption)
            }
        }
    }

    private func orderButton(_ title: String, symbol: String, action: (() -> Void)?) -> some View {
        Button {
            action?()
        } label: {
            Image(systemName: symbol).frame(width: 22, height: 20)
        }
        .buttonStyle(.borderless)
        .disabled(action == nil)
        .accessibilityLabel(title)
        .help(title)
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
