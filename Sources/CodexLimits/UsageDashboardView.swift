import CodexWidgetKit
import SwiftUI

struct UsageDashboardView: View {
    let period: UsagePeriod
    let window: UsageWindow
    let snapshot: UsageSnapshot
    let samples: [UsageSample]
    let now: Date
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage private var paceTargetCreditID: String
    @AppStorage private var chartRange: ChartRange
    @AppStorage private var savedBurndownTarget: Data
    @State private var datePickerSelection: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    init(
        provider: UsageProvider,
        period: UsagePeriod,
        window: UsageWindow,
        snapshot: UsageSnapshot,
        samples: [UsageSample],
        now: Date = .now,
        defaults: UserDefaults = .standard
    ) {
        self.period = period
        self.window = window
        self.snapshot = snapshot
        self.samples = samples
        self.now = now
        _safetyBuffer = AppStorage(wrappedValue: 3, UsageMonitor.safetyBufferKey, store: defaults)
        _paceTargetCreditID = AppStorage(
            wrappedValue: "",
            UsageDashboardPreferences.key(UsageMonitor.paceTargetCreditIDKey, provider: provider, period: period),
            store: defaults
        )
        _chartRange = AppStorage(
            wrappedValue: .window,
            UsageDashboardPreferences.key("chartRange", provider: provider, period: period),
            store: defaults
        )
        _savedBurndownTarget = AppStorage(
            wrappedValue: Data(),
            UsageDashboardPreferences.key("burndownTarget", provider: provider, period: period),
            store: defaults
        )
    }

    private var resetCredits: [ResetCredit] { period == .weekly ? snapshot.resetCredits : [] }

    var body: some View {
        Group {
            if window.resetsAt <= now {
                expiredDashboard
            } else {
                currentDashboard
            }
        }
        .task(id: burndownTarget) {
            guard let target = burndownTarget else { return }
            do {
                try await Task.sleep(for: .seconds(max(target.date.timeIntervalSinceNow, 0)))
                burndownTarget = nil
            } catch {}
        }
    }

    private var currentDashboard: some View {
        let target = activeTarget(in: window)
        let paceDeadline = target?.date ?? ForecastEngine.paceDeadline(
            window: window, resetCredits: resetCredits, now: now,
            selectedCreditID: paceTargetCreditID
        )
        let forecast = ForecastEngine.evaluate(
            window: window, samples: samples, tokenHistory: snapshot.tokenHistory,
            safetyBuffer: safetyBuffer, now: snapshot.fetchedAt,
            previousStatus: nil, deadline: paceDeadline
        )
        let accent = UsageChartStyle.accent(for: window.remainingPercent, scheme: colorScheme, selection: usageAccent)
        return VStack(alignment: .leading, spacing: 16) {
            PaceStatusView(
                status: forecast.status,
                message: StatusText.message(
                    forecast: forecast,
                    remainingPercent: window.remainingPercent,
                    fetchedAt: snapshot.fetchedAt,
                    deadline: paceDeadline,
                    windowReset: window.resetsAt,
                    safetyBuffer: safetyBuffer,
                    targetName: target == nil ? nil : "your pacing target"
                ),
                color: statusColor(forecast.status)
            )

            rangeControls

            if let duration = chartRange.duration {
                HistoryChart(
                    samples: samples,
                    range: snapshot.fetchedAt.addingTimeInterval(-duration) ... snapshot.fetchedAt,
                    bucketDuration: chartRange.bucketDuration,
                    visibleDuration: chartRange.visibleDuration,
                    remainingPercent: window.remainingPercent
                )
            } else {
                BurnDownChart(
                    window: window,
                    samples: UsageMonitor.windowSamples(samples, reset: window.resetsAt),
                    tokenHistory: snapshot.tokenHistory,
                    fetchedAt: snapshot.fetchedAt,
                    forecast: forecast,
                    safetyBuffer: safetyBuffer,
                    resetCredits: resetCredits,
                    paceDeadline: paceDeadline,
                    paceTargetCreditID: Binding(get: { target == nil ? paceTargetCreditID : "" }, set: {
                        burndownTarget = nil
                        paceTargetCreditID = $0
                    }),
                    customTargetDate: target?.date,
                    onSelectTarget: { date in
                        if let date {
                            selectTarget(date, in: window)
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
                    Text(window.resetsAt.formatted(date: .abbreviated, time: .shortened))
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
                        now: snapshot.fetchedAt,
                        targetName: paceDeadline == window.resetsAt ? "reset" : "target"
                    ))
                }
                .help("Usage budget that would leave your \(Int(safetyBuffer.rounded()))% reserve at \(paceDeadline.formatted(date: .abbreviated, time: .shortened)). Percentages refer to the full allowance for this period.")
                if !resetCredits.isEmpty {
                    GridRow(alignment: .firstTextBaseline) {
                        Text("Banked resets")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            bankedResetsMenu()
                            if target == nil, paceDeadline != window.resetsAt {
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
        }
    }

    private var expiredDashboard: some View {
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Label("Awaiting next reading", systemImage: "clock")
                    .font(.system(size: 12, weight: .semibold))
                Text("This period ended \(window.resetsAt.formatted(date: .abbreviated, time: .shortened)). The chart shows recorded history; a new reading is needed to show the current balance.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ChartRangePicker(selection: $chartRange, windowTitle: "Last period",
                             windowHelp: "Usage recorded during the last reported period.")
            if let duration = chartRange.duration {
                HistoryChart(samples: samples,
                             range: snapshot.fetchedAt.addingTimeInterval(-duration) ... snapshot.fetchedAt,
                             bucketDuration: chartRange.bucketDuration, visibleDuration: chartRange.visibleDuration,
                             remainingPercent: window.remainingPercent)
            } else {
                HistoryChart(samples: UsageMonitor.windowSamples(samples, reset: window.resetsAt),
                             range: window.startsAt ... window.resetsAt,
                             bucketDuration: 0, visibleDuration: nil,
                             remainingPercent: window.remainingPercent)
            }
        }
    }

    private var rangeControls: some View {
        let target = activeTarget(in: window)
        return HStack(spacing: 10) {
            ChartRangePicker(selection: $chartRange,
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
        burndownTarget.flatMap { $0.isValid(in: window, now: now) ? $0 : nil }
    }

    private func selectTarget(_ date: Date, in window: UsageWindow) {
        guard let target = BurndownTarget(date: date, window: window, now: .now) else { return }
        paceTargetCreditID = ""
        burndownTarget = date == window.resetsAt ? nil : target
        chartRange = .window
    }

    private func statusColor(_ status: PaceStatus) -> Color {
        switch status {
        case .slowDown: UsageChartStyle.accent(for: 0, scheme: colorScheme)
        case .onTrack, .roomToUseMore: UsageChartStyle.accent(for: 100, scheme: colorScheme, selection: usageAccent)
        }
    }

    private func bankedResetsMenu() -> some View {
        Menu {
            ForEach(resetCredits) { credit in
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
            bankedResetsLabel(resetCredits)
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
