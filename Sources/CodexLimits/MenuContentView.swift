import AppKit
import Charts
import CodexWidgetKit
import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(UsageMonitor.paceTargetCreditIDKey) private var paceTargetCreditID = ""
    @AppStorage("chartRange") private var chartRange = ChartRange.window
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let snapshot = monitor.snapshot, let forecast = monitor.forecast {
                dashboard(snapshot: snapshot, forecast: forecast)
            } else {
                emptyState
            }
        }
        .frame(width: 420)
        .padding(20)
        .background { UsageSurfaceBackground(remaining: monitor.snapshot?.mainLimit.window.remainingPercent) }
        .task { await monitor.refresh() }
        .onChange(of: paceTargetCreditID) { _, selectedCreditID in
            monitor.updatePaceTarget(selectedCreditID)
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private func dashboard(snapshot: UsageSnapshot, forecast: Forecast) -> some View {
        let paceDeadline = ForecastEngine.paceDeadline(
            window: snapshot.mainLimit.window,
            resetCredits: snapshot.resetCredits,
            now: snapshot.fetchedAt,
            selectedCreditID: paceTargetCreditID
        )
        let accent = UsageChartStyle.accent(for: snapshot.mainLimit.window.remainingPercent, scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 7) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("CODEX")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2)
                Spacer()
                Text(windowTitle(snapshot.mainLimit.window))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.4)
            }
            .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(snapshot.mainLimit.window.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 52, weight: .medium, design: .rounded))
                    .tracking(-2)
                    .monospacedDigit()
                Text("%")
                    .font(.system(size: 25, design: .rounded))
                    .foregroundStyle(accent)
                Text("remaining")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 5)
                Spacer()
                Button {
                    Task { await monitor.refresh() }
                } label: {
                    if monitor.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .help("Refresh")
                .accessibilityLabel("Refresh usage")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(StatusText.title(forecast.status))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(statusColor(forecast.status))
                Text(StatusText.message(
                    forecast: forecast,
                    remainingPercent: snapshot.mainLimit.window.remainingPercent,
                    fetchedAt: snapshot.fetchedAt,
                    deadline: paceDeadline,
                    windowReset: snapshot.mainLimit.window.resetsAt,
                    safetyBuffer: safetyBuffer
                ))
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
                .fixedSize(horizontal: false, vertical: true)
            }

            ChartRangePicker(selection: $chartRange, accent: accent)

            if let duration = chartRange.duration {
                HistoryChart(
                    samples: monitor.samples,
                    range: snapshot.fetchedAt.addingTimeInterval(-duration) ... snapshot.fetchedAt,
                    bucketDuration: chartRange.bucketDuration,
                    visibleDuration: chartRange.visibleDuration,
                    remainingPercent: snapshot.mainLimit.window.remainingPercent
                )
            } else {
                BurnDownChart(
                    window: snapshot.mainLimit.window,
                    samples: monitor.currentWindowSamples,
                    tokenHistory: snapshot.tokenHistory,
                    fetchedAt: snapshot.fetchedAt,
                    forecast: forecast,
                    safetyBuffer: safetyBuffer,
                    resetCredits: snapshot.resetCredits,
                    paceDeadline: paceDeadline,
                    paceTargetCreditID: $paceTargetCreditID
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                GridRow {
                    Text("Reset")
                        .foregroundStyle(.secondary)
                    Text(snapshot.mainLimit.window.resetsAt.formatted(date: .abbreviated, time: .shortened))
                }
                GridRow {
                    Text("Suggested pace")
                        .foregroundStyle(.secondary)
                    Text(StatusText.pace(
                        recommendedPercentPerDay: forecast.recommendedPercentPerDay,
                        deadline: paceDeadline,
                        now: snapshot.fetchedAt
                    ))
                }
                if !snapshot.resetCredits.isEmpty {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Banked resets")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            bankedResetsMenu(snapshot: snapshot)
                            if paceDeadline != snapshot.mainLimit.window.resetsAt {
                                HStack(spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 8))
                                    Text("Pacing to banked reset")
                                    Text(
                                        paceDeadline,
                                        format: .dateTime.month(.abbreviated).day().hour().minute()
                                    )
                                    .foregroundStyle(.secondary)
                                }
                                .font(.caption)
                                .foregroundStyle(Color.orange)
                            }
                        }
                    }
                }
            }
            .font(.system(size: 12))

            if !snapshot.otherLimits.isEmpty {
                Divider()
                Text("Other limits")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .textCase(.uppercase)
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
                ForEach(snapshot.otherLimits) { limit in
                    HStack {
                        Text(limit.name)
                            .lineLimit(1)
                        Spacer()
                        Text("\(Int(limit.window.remainingPercent.rounded()))%")
                            .monospacedDigit()
                        Text(limit.window.resetsAt, format: .dateTime.month(.abbreviated).day().hour().minute())
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

            Divider()
            HStack {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(StatusText.updated(snapshot.fetchedAt, now: context.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button {
                    openWindow(id: "widgets")
                    NSApp.activate(ignoringOtherApps: true)
                } label: {
                    Image(systemName: "rectangle.on.rectangle")
                }
                .buttonStyle(.borderless)
                .help("Preview widgets")
                .accessibilityLabel("Preview widgets")
                Button {
                    openSettings()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        NSApp.windows.first {
                            $0.isVisible && $0.styleMask.contains(.titled)
                        }?.orderFrontRegardless()
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            if monitor.isRefreshing {
                ProgressView()
                Text("Reading Codex usage…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                Text(monitor.errorMessage ?? "Codex usage is not available.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try Again") {
                    Task { await monitor.refresh() }
                }
            }
            Button("Preview widgets") {
                openWindow(id: "widgets")
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(.borderless)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func statusColor(_ status: PaceStatus) -> Color {
        switch status {
        case .slowDown: UsageChartStyle.accent(for: 0, scheme: colorScheme)
        case .onTrack, .roomToUseMore: UsageChartStyle.accent(for: 100, scheme: colorScheme)
        }
    }

    private func windowTitle(_ window: UsageWindow) -> String {
        switch window.durationMinutes {
        case 10_080: "THIS WEEK"
        case 300: "5-HOUR WINDOW"
        default: "CURRENT WINDOW"
        }
    }

    private func bankedResetsMenu(snapshot: UsageSnapshot) -> some View {
        let window = snapshot.mainLimit.window
        return Menu {
            ForEach(snapshot.resetCredits) { credit in
                Button {
                    paceTargetCreditID = paceTargetCreditID == credit.id ? "" : credit.id
                } label: {
                    let text = BankedResetPresentation.itemText(credit, windowReset: window.resetsAt)
                    if credit.id == paceTargetCreditID {
                        Label(text, systemImage: "checkmark")
                    } else {
                        Text(text)
                    }
                }
                .disabled(!BankedResetPresentation.qualifies(
                    credit,
                    now: snapshot.fetchedAt,
                    windowReset: window.resetsAt
                ))
            }
            Divider()
            Text(BankedResetPresentation.hint(hasSelection: !paceTargetCreditID.isEmpty))
        } label: {
            bankedResetsLabel(snapshot.resetCredits)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Expiry of the next banked reset. Pick one to pace toward it.")
    }

    private func bankedResetsLabel(_ credits: [ResetCredit]) -> Text {
        let parts = BankedResetPresentation.labelParts(for: credits)
        let head = Text(parts.head)
        guard let extra = parts.extra else { return head }
        return head + Text("  \(extra)").foregroundColor(.secondary)
    }
}

enum ChartRange: String, CaseIterable {
    case window
    case week
    case month

    var title: String {
        switch self {
        case .window: "Window"
        case .week: "7 days"
        case .month: "30 days"
        }
    }

    var duration: TimeInterval? {
        switch self {
        case .window: nil
        case .week, .month: 30 * 86_400
        }
    }

    var bucketDuration: TimeInterval {
        switch self {
        case .window: 0
        case .week, .month: 1_800
        }
    }

    var visibleDuration: TimeInterval? {
        switch self {
        case .window, .month: nil
        case .week: 7 * 86_400
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(LoginItem.preferenceKey) private var launchAtLogin = true
    @AppStorage(BackgroundCollection.preferenceKey) private var collectInBackground = false
    @State private var loginItemError: String?
    @State private var backgroundCollectionError: String?

    var body: some View {
        Form {
            Stepper(value: $safetyBuffer, in: 1 ... 10, step: 1) {
                Text("Safety buffer: \(Int(safetyBuffer))%")
            }
            .onChange(of: safetyBuffer) { _, value in
                monitor.updateSafetyBuffer(value)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: updateLaunchAtLogin
            ))

            if let loginItemError {
                Text(loginItemError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Background collection") {
                Toggle("Collect usage while the app is closed", isOn: Binding(
                    get: { collectInBackground },
                    set: updateBackgroundCollection
                ))

                Text("A background helper records a usage sample every 15 minutes, so charts stay complete for periods when the app isn’t running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if BackgroundCollection.service.status == .requiresApproval {
                    Label(
                        "Allow Codex Limits in System Settings → Login Items to enable background collection.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if let backgroundCollectionError {
                    Text(backgroundCollectionError)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History sync") {
                Text("Keep usage history in a folder available on your other Macs.")
                    .foregroundStyle(.secondary)

                if let folderName = monitor.syncFolderName {
                    LabeledContent("Folder", value: folderName)
                    Button("Stop Syncing") {
                        Task { await monitor.stopHistorySync() }
                    }
                } else {
                    Button("Choose Folder…", action: chooseHistoryFolder)
                }

                Text("Use this folder only on Macs signed in to the same Codex account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Choose a private folder that isn’t shared with other people.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let syncErrorMessage = monitor.syncErrorMessage {
                    Label(syncErrorMessage, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 380)
    }

    private func updateLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled, SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            } else if !enabled, SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            launchAtLogin = enabled
            loginItemError = nil
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
            loginItemError = "Couldn’t update the login setting."
        }
    }

    private func updateBackgroundCollection(_ enabled: Bool) {
        do {
            if enabled, BackgroundCollection.service.status != .enabled {
                try BackgroundCollection.service.register()
            } else if !enabled, BackgroundCollection.service.status == .enabled {
                try BackgroundCollection.service.unregister()
            }
            collectInBackground = enabled
            backgroundCollectionError = nil
        } catch {
            collectInBackground = BackgroundCollection.service.status == .enabled
            backgroundCollectionError = "Couldn’t update background collection."
        }
    }

    private func chooseHistoryFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        guard panel.runModal() == .OK, let directory = panel.url else { return }
        Task { await monitor.connectHistoryFolder(directory) }
    }
}

enum BackgroundCollection {
    static let preferenceKey = "collectInBackground"
    static let agentPlistName = "com.github.nserfan.CodexLimits.collector.plist"

    static var service: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    static func enableByDefault() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) == nil else { return }
        // Registration pins the agent to this bundle's location, so a bare
        // `swift run` binary must not claim it before the installed app can.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        do {
            if service.status != .enabled {
                try service.register()
            }
            defaults.set(true, forKey: preferenceKey)
        } catch {
            defaults.set(false, forKey: preferenceKey)
        }
    }
}

enum LoginItem {
    static let preferenceKey = "launchAtLogin"

    static func enableByDefault() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: preferenceKey) == nil else { return }
        do {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
            defaults.set(true, forKey: preferenceKey)
        } catch {
            defaults.set(false, forKey: preferenceKey)
        }
    }
}
