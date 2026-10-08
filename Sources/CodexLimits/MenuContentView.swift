import AppKit
import CodexWidgetKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: UsageMonitor
    @Binding var selectedProvider: UsageProvider
    var providerOptions: [UsageProvider]
    var onSignIn: () -> Void
    var loginMessage: String?
    var isOpeningLogin: Bool
    var showsFooterActions: Bool
    var refreshesOnAppear: Bool
    private let defaults: UserDefaults
    @AppStorage private var savedPeriod: String
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    init(
        monitor: UsageMonitor,
        selectedProvider: Binding<UsageProvider>? = nil,
        providerOptions: [UsageProvider] = UsageProvider.allCases,
        onSignIn: @escaping () -> Void = {},
        loginMessage: String? = nil,
        isOpeningLogin: Bool = false,
        showsFooterActions: Bool = true,
        refreshesOnAppear: Bool = true,
        defaults: UserDefaults = .standard
    ) {
        self.monitor = monitor
        self.defaults = defaults
        _selectedProvider = selectedProvider ?? .constant(monitor.provider)
        self.providerOptions = providerOptions
        self.onSignIn = onSignIn
        self.loginMessage = loginMessage
        self.isOpeningLogin = isOpeningLogin
        self.showsFooterActions = showsFooterActions
        self.refreshesOnAppear = refreshesOnAppear
        _savedPeriod = AppStorage(wrappedValue: "", UsageDashboardPreferences.selectionKey(for: monitor.provider), store: defaults)
    }

    var body: some View {
        VStack(spacing: 16) {
            ProviderPicker(selection: $selectedProvider, options: providerOptions)
                .frame(maxWidth: 320)
            if let snapshot = monitor.snapshot {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    dashboard(snapshot: snapshot, now: context.date)
                }
            } else {
                emptyState
            }
        }
        .frame(width: 420)
        .padding(20)
        .background { UsageSurfaceBackground(remaining: selectedWindow?.remainingPercent) }
        .tint(UsageChartStyle.accent(for: nil, scheme: colorScheme, selection: usageAccent))
        .task {
            if refreshesOnAppear { await monitor.refresh() }
        }
        .onChange(of: monitor.snapshot, initial: true) { _, snapshot in
            if let snapshot {
                UsageDashboardPreferences.migrateLegacyPreferences(snapshot: snapshot, provider: monitor.provider, defaults: defaults)
            }
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private var selectedWindow: UsageWindow? {
        guard let snapshot = monitor.snapshot,
              let period = UsageDashboardPreferences.selectedPeriod(savedValue: savedPeriod, snapshot: snapshot, provider: monitor.provider) else {
            return nil
        }
        return snapshot.limit(for: period, provider: monitor.provider)?.window
    }

    private func dashboard(snapshot: UsageSnapshot, now: Date) -> some View {
        let period = UsageDashboardPreferences.selectedPeriod(savedValue: savedPeriod, snapshot: snapshot, provider: monitor.provider)
        let otherLimits = UsageDashboardPreferences.otherLimits(in: snapshot, provider: monitor.provider)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                ProviderIcon(provider: monitor.provider, size: 14)
                Text(monitor.provider.displayName.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                Spacer()
                refreshButton
            }
            .foregroundStyle(.secondary)

            if snapshot.limit(for: .fiveHour, provider: monitor.provider) != nil {
                UsagePeriodPicker(snapshot: snapshot, provider: monitor.provider, selection: period, now: now,
                                  onSelect: { savedPeriod = $0.rawValue })
            } else if let period, let window = snapshot.limit(for: period, provider: monitor.provider)?.window {
                balance(period: period, window: window, now: now)
            }

            if let period, let limit = snapshot.limit(for: period, provider: monitor.provider) {
                UsageDashboardView(provider: monitor.provider, period: period, window: limit.window,
                                   snapshot: snapshot, samples: monitor.samples(for: period), now: now, defaults: defaults)
                    .id(period)
            } else {
                Text("Account limits are not reported for this account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !otherLimits.isEmpty {
                Divider()
                Text("Other limits")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                ForEach(otherLimits) { limit in
                    HStack {
                        Text(limit.name).lineLimit(1)
                        Spacer()
                        Text("\(Int(limit.window.remainingPercent.rounded()))% remaining")
                            .monospacedDigit()
                        Text("Resets \(limit.window.resetsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 11))
                }
            }

            if let error = monitor.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if monitor.requiresLogin { signInControls }
            Divider()
            footer(snapshot: snapshot)
        }
    }

    private func balance(period: UsagePeriod, window: UsageWindow, now: Date) -> some View {
        let hasExpired = window.resetsAt <= now
        let accent = UsageChartStyle.accent(for: window.remainingPercent, scheme: colorScheme, selection: usageAccent)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(window.remainingPercent, format: .number.precision(.fractionLength(0)))
                .font(.system(size: 52, weight: .medium, design: .rounded))
                .tracking(-2)
                .monospacedDigit()
            Text("%")
                .font(.system(size: 25, design: .rounded))
                .foregroundStyle(accent)
            Text(hasExpired ? "last \(period.title.lowercased()) reading" : "\(period.title.lowercased()) allowance left")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.leading, 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hasExpired
            ? "\(period.title) limit, last reading \(Int(window.remainingPercent.rounded())) percent, awaiting next reading"
            : "\(period.title) limit, \(Int(window.remainingPercent.rounded())) percent remaining")
    }

    private var refreshButton: some View {
        Button {
            Task { await monitor.refresh() }
        } label: {
            if monitor.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .disabled(monitor.isRefreshing)
        .help("Refresh usage")
        .accessibilityLabel("Refresh usage")
    }

    private func footer(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(StatusText.updated(snapshot.fetchedAt, now: context.date))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if monitor.errorMessage == nil, let message = monitor.refreshMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if showsFooterActions {
                footerActions
            }
        }
    }

    private var footerActions: some View {
        HStack(spacing: 16) {
            if monitor.provider == .codex {
                activityButton
            }
            Button {
                openSettings()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.windows.first {
                        $0.isVisible && $0.styleMask.contains(.titled)
                    }?.orderFrontRegardless()
                }
            } label: {
                Label("Settings", systemImage: "gearshape")
                    .padding(.horizontal, 6).frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Text("Quit").padding(.horizontal, 6).frame(minHeight: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
        }
    }

    private var activityButton: some View {
        Button {
            openWindow(id: "model-activity")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Activity", systemImage: "chart.bar.xaxis")
                .padding(.horizontal, 6).frame(minHeight: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Explore usage by model and reasoning effort.")
        .accessibilityLabel("Open model activity")
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if monitor.isRefreshing {
                ProgressView()
                Text("Checking \(monitor.provider.displayName) usage…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                Text(monitor.errorMessage ?? monitor.refreshMessage ?? "Usage is unavailable. Try refreshing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await monitor.refresh() }
                }
                if monitor.requiresLogin {
                    signInControls
                }
            }
            if showsFooterActions {
                Divider()
                footerActions
            }
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private var signInControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button("Sign in to \(monitor.provider.displayName)…", action: onSignIn)
                .disabled(isOpeningLogin)
            if let loginMessage {
                Text(loginMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Link("Install \(monitor.provider.cliDisplayName)", destination: ProviderLogin.installationURL(for: monitor.provider))
                .font(.caption)
        }
    }

}
