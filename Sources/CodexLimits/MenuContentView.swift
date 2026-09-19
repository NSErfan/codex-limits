import AppKit
import Charts
import CodexWidgetKit
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(UsageMonitor.paceTargetCreditIDKey) private var paceTargetCreditID = ""
    @AppStorage("chartRange") private var chartRange = ChartRange.window
    @AppStorage("burndownTarget") private var savedBurndownTarget = Data()
    @State private var datePickerSelection: Date?
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

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
        .tint(UsageChartStyle.accent(for: nil, scheme: colorScheme, selection: usageAccent))
        .task { await monitor.refresh() }
        .onChange(of: paceTargetCreditID) { _, selectedCreditID in
            monitor.updatePaceTarget(selectedCreditID)
        }
        .task(id: burndownTarget) {
            guard let target = burndownTarget else { return }
            do {
                try await Task.sleep(for: .seconds(max(target.date.timeIntervalSinceNow, 0)))
                burndownTarget = nil
            } catch {}
        }
        .environment(\.locale, Locale(identifier: "en_US"))
    }

    private func dashboard(snapshot: UsageSnapshot, forecast liveForecast: Forecast) -> some View {
        let target = activeTarget(in: snapshot.mainLimit.window)
        let paceDeadline = target?.date ?? ForecastEngine.paceDeadline(
            window: snapshot.mainLimit.window,
            resetCredits: snapshot.resetCredits,
            now: snapshot.fetchedAt,
            selectedCreditID: paceTargetCreditID
        )
        let forecast = target == nil ? liveForecast : ForecastEngine.evaluate(
            window: snapshot.mainLimit.window, samples: monitor.samples,
            tokenHistory: snapshot.tokenHistory, safetyBuffer: safetyBuffer,
            now: snapshot.fetchedAt, previousStatus: nil, deadline: paceDeadline
        )
        let accent = UsageChartStyle.accent(for: snapshot.mainLimit.window.remainingPercent, scheme: colorScheme, selection: usageAccent)
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
                .help("Refresh usage")
                .accessibilityLabel("Refresh usage")
            }

            PaceStatusView(
                status: forecast.status,
                message: StatusText.message(
                    forecast: forecast,
                    remainingPercent: snapshot.mainLimit.window.remainingPercent,
                    fetchedAt: snapshot.fetchedAt,
                    deadline: paceDeadline,
                    windowReset: snapshot.mainLimit.window.resetsAt,
                    safetyBuffer: safetyBuffer,
                    targetName: target == nil ? nil : "your pacing target"
                ),
                color: statusColor(forecast.status)
            )

            rangeControls(snapshot: snapshot, accent: accent)

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
                    paceTargetCreditID: Binding(get: { target == nil ? paceTargetCreditID : "" }, set: {
                        burndownTarget = nil
                        paceTargetCreditID = $0
                    }),
                    customTargetDate: target?.date,
                    onSelectTarget: { date in
                        if let date {
                            selectTarget(date, in: snapshot.mainLimit.window)
                        } else {
                            burndownTarget = nil
                        }
                    }
                )
            }

            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                GridRow {
                    Text("Scheduled reset")
                        .foregroundStyle(.secondary)
                    Text(snapshot.mainLimit.window.resetsAt.formatted(date: .abbreviated, time: .shortened))
                }
                if let target {
                    GridRow {
                        Text("Pacing target").foregroundStyle(.secondary)
                        Text(target.date.formatted(date: .abbreviated, time: .shortened))
                            .foregroundStyle(accent)
                    }
                }
                GridRow {
                    Text("Usage budget")
                        .foregroundStyle(.secondary)
                    Text(StatusText.pace(
                        recommendedPercentPerDay: forecast.recommendedPercentPerDay,
                        deadline: paceDeadline,
                        now: snapshot.fetchedAt
                    ))
                }
                .help("Average usage that would leave your \(Int(safetyBuffer.rounded()))% reserve at \(paceDeadline.formatted(date: .abbreviated, time: .shortened)). Percentages refer to the full allowance for this period.")
                if !snapshot.resetCredits.isEmpty {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Banked resets")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            bankedResetsMenu(snapshot: snapshot)
                            if target == nil, paceDeadline != snapshot.mainLimit.window.resetsAt {
                                HStack(alignment: .firstTextBaseline, spacing: 3) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 8))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Pacing target")
                                            .fontWeight(.medium)
                                        Text("Banked reset expiry · \(paceDeadline, format: .dateTime.month(.abbreviated).day().hour().minute())")
                                        .lineLimit(1)
                                        .fixedSize()
                                    }
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

            Divider()
            footer(snapshot: snapshot)
        }
    }

    private func footer(snapshot: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text(StatusText.updated(snapshot.fetchedAt, now: context.date))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                activityButton
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
    }

    private func rangeControls(snapshot: UsageSnapshot, accent: Color) -> some View {
        let window = snapshot.mainLimit.window
        let target = activeTarget(in: window)
        return HStack(spacing: 10) {
            ChartRangePicker(selection: $chartRange, accent: accent,
                             windowHelp: target == nil ? "Option-click to choose a pacing target." : "Option-click to use the scheduled reset.",
                             onOptionClickWindow: {
                if target != nil {
                    burndownTarget = nil
                } else if window.resetsAt > Date.now {
                    datePickerSelection = window.resetsAt
                }
                chartRange = .window
            })
            if let target {
                Button {
                    datePickerSelection = target.date
                } label: {
                    Image(systemName: "clock").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Change pacing target")
                .help("Choose a pacing target or use the scheduled reset.")
            }
        }
        .popover(isPresented: Binding(get: { datePickerSelection != nil }, set: { if !$0 { datePickerSelection = nil } })) {
            if let draft = datePickerSelection {
                ForecastTargetPicker(window: window, initialDate: draft,
                                     onCancel: { datePickerSelection = nil }, onSelect: { date in
                    selectTarget(date, in: window)
                    datePickerSelection = nil
                }, onReset: {
                    burndownTarget = nil
                    paceTargetCreditID = ""
                    datePickerSelection = nil
                })
            }
        }
    }

    private var burndownTarget: BurndownTarget? {
        get { try? JSONDecoder().decode(BurndownTarget.self, from: savedBurndownTarget) }
        nonmutating set {
            savedBurndownTarget = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        }
    }

    private func activeTarget(in window: UsageWindow) -> BurndownTarget? {
        burndownTarget.flatMap { $0.isValid(in: window, now: .now) ? $0 : nil }
    }

    private func selectTarget(_ date: Date, in window: UsageWindow) {
        guard let target = BurndownTarget(date: date, window: window, now: .now) else { return }
        paceTargetCreditID = ""
        burndownTarget = date == window.resetsAt ? nil : target
        chartRange = .window
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
                Text("Checking Codex usage…")
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                Text(monitor.errorMessage ?? "Usage is unavailable. Try refreshing.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await monitor.refresh() }
                }
            }
            activityButton
        }
        .frame(maxWidth: .infinity, minHeight: 170)
    }

    private func statusColor(_ status: PaceStatus) -> Color {
        switch status {
        case .slowDown: UsageChartStyle.accent(for: 0, scheme: colorScheme)
        case .onTrack, .roomToUseMore: UsageChartStyle.accent(for: 100, scheme: colorScheme, selection: usageAccent)
        }
    }

    private func windowTitle(_ window: UsageWindow) -> String {
        switch window.durationMinutes {
        case 10_080: "WEEKLY LIMIT"
        case 300: "5-HOUR LIMIT"
        default: "CURRENT LIMIT"
        }
    }

    private func bankedResetsMenu(snapshot: UsageSnapshot) -> some View {
        let window = snapshot.mainLimit.window
        return Menu {
            ForEach(snapshot.resetCredits) { credit in
                Button {
                    burndownTarget = nil
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
            Text("Selecting a pacing target does not use a banked reset.")
        } label: {
            bankedResetsLabel(snapshot.resetCredits)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Next known banked reset expiry. Choose a reset to use its expiry as your pacing target.")
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
        case .window: "Current period"
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
