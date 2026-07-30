import AppKit
import Charts
import ServiceManagement
import SwiftUI

struct MenuContentView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(UsageMonitor.paceTargetCreditIDKey) private var paceTargetCreditID = ""
    @AppStorage("chartRange") private var chartRange = ChartRange.window
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if let snapshot = monitor.snapshot, let forecast = monitor.forecast {
                dashboard(snapshot: snapshot, forecast: forecast)
            } else {
                emptyState
            }
        }
        .frame(width: 420)
        .padding(16)
        .task { await monitor.refresh() }
        .onChange(of: paceTargetCreditID) { _, _ in
            monitor.updatePaceTarget()
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
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(snapshot.mainLimit.window.remainingPercent, format: .number.precision(.fractionLength(0)))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("% remaining")
                    .foregroundStyle(.secondary)
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
                Text(statusTitle(forecast.status))
                    .font(.headline)
                    .foregroundStyle(statusColor(forecast.status))
                Text(statusMessage(snapshot: snapshot, forecast: forecast, deadline: paceDeadline))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GlassSegmentedPicker(selection: $chartRange)

            if let duration = chartRange.duration {
                HistoryChart(
                    samples: monitor.samples,
                    range: snapshot.fetchedAt.addingTimeInterval(-duration) ... snapshot.fetchedAt,
                    bucketDuration: chartRange.bucketDuration,
                    visibleDuration: chartRange.visibleDuration
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
                    Text(paceText(forecast: forecast, reset: paceDeadline))
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
            .font(.callout)

            if !snapshot.otherLimits.isEmpty {
                Divider()
                Text("Other limits")
                    .font(.caption)
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
                    .font(.caption)
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
                    Text(updatedText(snapshot.fetchedAt, now: context.date))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
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
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private func statusTitle(_ status: PaceStatus) -> String {
        switch status {
        case .slowDown: "Slow down"
        case .onTrack: "On track"
        case .roomToUseMore: "Room to use more"
        }
    }

    private func statusColor(_ status: PaceStatus) -> Color {
        switch status {
        case .slowDown: .red
        case .onTrack: .green
        case .roomToUseMore: .blue
        }
    }

    private func statusMessage(snapshot: UsageSnapshot, forecast: Forecast, deadline: Date) -> String {
        let target = deadline == snapshot.mainLimit.window.resetsAt
            ? "reset"
            : "banked reset expiry"
        switch forecast.status {
        case .slowDown:
            let window = snapshot.mainLimit.window
            let timeLeft = deadline.timeIntervalSince(snapshot.fetchedAt)
            let timeToEmpty = window.remainingPercent / max(forecast.safetyPercentPerDay, 0.01) * 86_400
            let early = max(timeLeft - timeToEmpty, 0)
            return early > 0
                ? "At this pace, your limit may run out \(durationText(early)) before the \(target)."
                : "Your current pace is too close to the limit."
        case .onTrack:
            return "You’re on track to have \(Int(forecast.expectedRemainingAtReset.rounded()))% left at the \(target)."
        case .roomToUseMore:
            let room = max(forecast.expectedRemainingAtReset - safetyBuffer, 0)
            return "You can use about \(Int(room.rounded()))% more before the \(target)."
        }
    }

    private func bankedResetsMenu(snapshot: UsageSnapshot) -> some View {
        let window = snapshot.mainLimit.window
        return Menu {
            ForEach(snapshot.resetCredits) { credit in
                let qualifies = credit.expiresAt
                    .map { $0 > snapshot.fetchedAt && $0 < window.resetsAt } == true
                Button {
                    paceTargetCreditID = paceTargetCreditID == credit.id ? "" : credit.id
                } label: {
                    if credit.id == paceTargetCreditID {
                        Label(creditItemText(credit), systemImage: "checkmark")
                    } else {
                        Text(creditItemText(credit))
                    }
                }
                .disabled(!qualifies)
            }
            Divider()
            Text(menuHint)
        } label: {
            bankedResetsLabel(snapshot.resetCredits)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Expiry of the next banked reset. Pick one to pace toward it.")
    }

    private func bankedResetsLabel(_ credits: [ResetCredit]) -> Text {
        let head = Text(
            credits.compactMap(\.expiresAt).min().map { creditDateText($0) } ?? "No expiry"
        )
        let extra = credits.count - 1
        guard extra > 0 else { return head }
        return head + Text("  +\(extra) more").foregroundColor(.secondary)
    }

    private var menuHint: String {
        paceTargetCreditID.isEmpty
            ? "Pick a banked reset to pace toward its expiry."
            : "Pick the checked reset again to pace to the window reset."
    }

    private func creditItemText(_ credit: ResetCredit) -> String {
        let title = credit.title ?? "Banked reset"
        guard let expiresAt = credit.expiresAt else { return "\(title) · no expiry" }
        let window = monitor.snapshot?.mainLimit.window
        let suffix = window.map { expiresAt >= $0.resetsAt ? " · after the next reset" : "" } ?? ""
        return "\(title) · expires \(creditDateText(expiresAt))\(suffix)"
    }

    private func creditDateText(_ date: Date?) -> String {
        guard let date else { return "no expiry" }
        return date.formatted(
            .dateTime.month(.abbreviated).day().hour().minute()
                .locale(Locale(identifier: "en_US"))
        )
    }

    private func paceText(forecast: Forecast, reset: Date) -> String {
        if reset.timeIntervalSinceNow <= 86_400 {
            return "Up to \(oneDecimal(forecast.recommendedPercentPerDay / 24))% an hour"
        }
        return "Up to \(oneDecimal(forecast.recommendedPercentPerDay))% a day"
    }

    private func oneDecimal(_ value: Double) -> String {
        value.formatted(
            .number
                .precision(.fractionLength(1))
                .locale(Locale(identifier: "en_US"))
        )
    }

    private func durationText(_ seconds: TimeInterval) -> String {
        if seconds >= 86_400 {
            let days = max(Int((seconds / 86_400).rounded()), 1)
            return "\(days) \(days == 1 ? "day" : "days")"
        }
        let hours = max(Int((seconds / 3_600).rounded()), 1)
        return "\(hours) \(hours == 1 ? "hour" : "hours")"
    }

    private func updatedText(_ date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        if seconds < 60 { return "Updated just now" }
        if seconds < 3_600 { return "Updated \(Int(seconds / 60)) min ago" }
        if seconds < 86_400 {
            let hours = Int(seconds / 3_600)
            return "Updated \(hours) \(hours == 1 ? "hr" : "hrs") ago"
        }
        let days = Int(seconds / 86_400)
        return "Updated \(days) \(days == 1 ? "day" : "days") ago"
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

private struct GlassSegmentedPicker: View {
    @Binding var selection: ChartRange
    @Namespace private var thumbNamespace

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 2) { track }
        } else {
            track
        }
    }

    private var track: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                segment(for: range)
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        }
    }

    private func segment(for range: ChartRange) -> some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                selection = range
            }
        } label: {
            label(for: range)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selection == range ? [.isSelected] : [])
    }

    @ViewBuilder
    private func label(for range: ChartRange) -> some View {
        let text = Text(range.title)
            .font(.callout.weight(selection == range ? .semibold : .regular))
            .foregroundStyle(selection == range ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
        if #available(macOS 26.0, *) {
            if selection == range {
                text
                    .glassEffect(.regular.interactive(), in: Capsule())
                    .glassEffectID("thumb", in: thumbNamespace)
            } else {
                text
            }
        } else {
            text.background {
                if selection == range {
                    Capsule()
                        .fill(.regularMaterial)
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.25), lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                        .matchedGeometryEffect(id: "thumb", in: thumbNamespace)
                }
            }
        }
    }
}

private struct HistoryChart: View {
    let samples: [UsageSample]
    let range: ClosedRange<Date>
    let bucketDuration: TimeInterval
    let visibleDuration: TimeInterval?

    @State private var selectedDate: Date?

    private var series: HistorySeriesBuilder.Series {
        HistorySeriesBuilder.series(from: samples, in: range, bucketDuration: bucketDuration)
    }

    private var axisDayStride: Int {
        visibleDuration == nil ? 5 : 1
    }

    private var hoveredPoint: HistorySeriesBuilder.Point? {
        guard let selectedDate else { return nil }
        return series.runs
            .flatMap(\.points)
            .min {
                abs($0.date.timeIntervalSince(selectedDate))
                    < abs($1.date.timeIntervalSince(selectedDate))
            }
    }

    private var hoveredReset: Date? {
        guard let selectedDate else { return nil }
        let visible = visibleDuration ?? range.upperBound.timeIntervalSince(range.lowerBound)
        return series.resets
            .min { abs($0.timeIntervalSince(selectedDate)) < abs($1.timeIntervalSince(selectedDate)) }
            .flatMap { abs($0.timeIntervalSince(selectedDate)) <= visible * 0.015 ? $0 : nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            readout
            if series.isEmpty {
                Text("No history yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else if let visibleDuration {
                chart
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: visibleDuration)
                    .chartScrollPosition(
                        initialX: range.upperBound.addingTimeInterval(-visibleDuration)
                    )
            } else {
                chart
            }
        }
        .padding(.horizontal, 8)
    }

    private var readout: some View {
        HStack(spacing: 4) {
            Spacer()
            if let hoveredReset {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.green)
                Text("Reset")
                    .foregroundStyle(Color.green)
                Text(
                    hoveredReset,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .foregroundStyle(.secondary)
            } else if let hovered = hoveredPoint {
                Text("\(Int(hovered.remainingPercent.rounded()))%")
                    .fontWeight(.semibold)
                Text(
                    hovered.date,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .monospacedDigit()
        .frame(height: 12)
    }

    private var chart: some View {
        Chart {
            ForEach(series.connectors) { connector in
                ForEach([connector.start, connector.end], id: \.date) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Remaining", point.remainingPercent),
                        series: .value("Series", "gap-\(connector.id)")
                    )
                    .foregroundStyle(Color.blue.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
                }
            }

            ForEach(series.runs) { run in
                if run.points.count == 1, let point = run.points.first {
                    PointMark(
                        x: .value("Time", point.date),
                        y: .value("Remaining", point.remainingPercent)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(20)
                } else {
                    ForEach(run.points, id: \.date) { point in
                        LineMark(
                            x: .value("Time", point.date),
                            y: .value("Remaining", point.remainingPercent),
                            series: .value("Series", "run-\(run.id)")
                        )
                        .foregroundStyle(Color.blue)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                    }
                }
            }

            ForEach(series.resets, id: \.self) { resetDate in
                RuleMark(x: .value("Reset", resetDate))
                    .foregroundStyle(Color.green.opacity(resetDate == hoveredReset ? 0.9 : 0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if hoveredReset == nil, let hovered = hoveredPoint {
                RuleMark(x: .value("Hovered", hovered.date))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                PointMark(
                    x: .value("Hovered", hovered.date),
                    y: .value("Remaining", hovered.remainingPercent)
                )
                .foregroundStyle(Color.blue)
                .symbolSize(55)
            }
        }
        .chartXSelection(value: $selectedDate)
        .onTapGesture {
            // A click pins the chart selection on macOS; release it so the
            // readout follows the pointer again instead of freezing.
            DispatchQueue.main.async { selectedDate = nil }
        }
        .onContinuousHover { phase in
            // chartXSelection does not reliably clear when the pointer
            // leaves the plot, which froze the readout in place.
            if case .ended = phase { selectedDate = nil }
        }
        .chartXScale(domain: range)
        .chartYScale(domain: 0 ... 100)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: axisDayStride)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(length: 3)
                    .foregroundStyle(Color.secondary)
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date, format: .dateTime.month(.abbreviated).day())
                    }
                }
                .foregroundStyle(Color.secondary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                    .foregroundStyle(Color.secondary.opacity(0.2))
                AxisTick(length: 3)
                    .foregroundStyle(Color.secondary)
                AxisValueLabel {
                    if let percent = value.as(Double.self) {
                        Text("\(Int(percent))%")
                    }
                }
                .foregroundStyle(Color.secondary)
            }
        }
        .chartLegend(.hidden)
        .frame(height: 190)
        .accessibilityLabel("Usage history")
        .accessibilityValue(accessibilitySummary)
    }

    private var accessibilitySummary: String {
        let days = Int(range.upperBound.timeIntervalSince(range.lowerBound) / 86_400)
        guard let latest = series.latestPoint else {
            return "No usage history in the last \(days) days."
        }
        let gaps = series.connectors.isEmpty
            ? ""
            : " \(series.connectors.count) gaps are shown as estimated connectors."
        return "Remaining percentage over the last \(days) days, most recently \(Int(latest.remainingPercent.rounded())) percent.\(gaps)"
    }
}

private struct BurnDownChart: View {
    let window: UsageWindow
    let samples: [UsageSample]
    let tokenHistory: [TokenDay]
    let fetchedAt: Date
    let forecast: Forecast
    let safetyBuffer: Double
    let resetCredits: [ResetCredit]
    let paceDeadline: Date
    @Binding var paceTargetCreditID: String

    @State private var selectedDate: Date?

    private var hoveredPoint: BurnPoint? {
        guard let selectedDate else { return nil }
        return observed.min {
            abs($0.date.timeIntervalSince(selectedDate))
                < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    private var visibleCredits: [ResetCredit] {
        resetCredits.filter { credit in
            guard let expiresAt = credit.expiresAt else { return false }
            return expiresAt > window.startsAt && expiresAt < window.resetsAt
        }
    }

    private var hoveredCredit: ResetCredit? {
        guard let selectedDate else { return nil }
        let span = window.resetsAt.timeIntervalSince(window.startsAt)
        return visibleCredits
            .compactMap { credit in
                credit.expiresAt.map { (credit: credit, distance: abs($0.timeIntervalSince(selectedDate))) }
            }
            .min { $0.distance < $1.distance }
            .flatMap { $0.distance <= span * 0.015 ? $0.credit : nil }
    }

    private var observed: [BurnPoint] {
        let current = BurnPoint(date: fetchedAt, remaining: window.remainingPercent)
        let local = samples
            .filter { $0.observedAt > window.startsAt && $0.observedAt < fetchedAt }
            .map { BurnPoint(date: $0.observedAt, remaining: $0.remainingPercent) }
            .sorted { $0.date < $1.date }
        let firstKnown = local.first ?? current
        let buckets = tokenHistory
            .filter {
                $0.date.addingTimeInterval(86_400) > window.startsAt && $0.date < firstKnown.date
            }
            .sorted { $0.date < $1.date }
        let totalTokens = buckets.reduce(Int64(0)) { $0 + $1.tokens }
        var bootstrapped: [BurnPoint] = []

        if totalTokens > 0 {
            var cumulativeTokens: Int64 = 0
            for bucket in buckets {
                cumulativeTokens += bucket.tokens
                let date = min(
                    max(bucket.date.addingTimeInterval(86_400), window.startsAt),
                    firstKnown.date
                )
                let used = (100 - firstKnown.remaining) * Double(cumulativeTokens) / Double(totalTokens)
                bootstrapped.append(BurnPoint(date: date, remaining: 100 - used))
            }
        }

        // Daily token buckets seed the curve until percentage samples cover the window.
        return deduplicated(
            [BurnPoint(date: window.startsAt, remaining: 100)] + bootstrapped + local + [current]
        )
    }

    private var currentColor: Color {
        forecast.currentPercentPerDay > forecast.historicalPercentPerDay ? .red : .blue
    }

    private var currentProjection: [BurnPoint] {
        projection(rate: forecast.currentPercentPerDay, remainingAtReset: forecast.expectedRemainingAtReset)
    }

    private var historicalProjection: [BurnPoint] {
        projection(rate: forecast.historicalPercentPerDay, remainingAtReset: forecast.historicalRemainingAtReset)
    }

    private var xAxisDates: [Date] {
        let step: TimeInterval = window.durationMinutes <= 24 * 60 ? 3_600 : 86_400
        var dates: [Date] = []
        var date = window.startsAt
        while date < window.resetsAt {
            dates.append(date)
            date = date.addingTimeInterval(step)
        }
        dates.append(window.resetsAt)
        return dates
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let credit = hoveredCredit, let expiresAt = credit.expiresAt {
                    Spacer()
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 8))
                        Text("Banked \(credit.title?.lowercased() ?? "reset")")
                        Text(
                            "expires \(expiresAt.formatted(.dateTime.month(.abbreviated).day().hour().minute()))"
                        )
                        .foregroundStyle(.secondary)
                        Text(credit.id == paceTargetCreditID ? "· click to stop pacing" : "· click to pace here")
                            .foregroundStyle(.secondary)
                            .italic()
                    }
                    .font(.caption)
                    .foregroundStyle(Color.orange)
                } else if let hovered = hoveredPoint {
                    Spacer()
                    HStack(spacing: 4) {
                        Text("\(Int(hovered.remaining.rounded()))%")
                            .fontWeight(.semibold)
                        Text(
                            hovered.date,
                            format: .dateTime.month(.abbreviated).day().hour().minute()
                        )
                        .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                    .monospacedDigit()
                } else {
                    ChartLegendItem(label: "Target", color: .green, dash: [3, 3])
                    ChartLegendItem(label: "Actual", color: .blue)
                    ChartLegendItem(label: "Current", color: currentColor, dash: [7, 3])
                    ChartLegendItem(label: "Historical", color: .secondary, dash: [2, 3])
                }
            }
            .frame(height: 16)

            Chart {
                ForEach([
                    BurnPoint(date: window.startsAt, remaining: 100),
                    BurnPoint(date: paceDeadline, remaining: 0)
                ]) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Target", point.remaining),
                        series: .value("Series", "Target")
                    )
                    .foregroundStyle(Color.green.opacity(0.75))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }

                ForEach(observed) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Actual", point.remaining),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(Color.blue)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .interpolationMethod(.stepEnd)
                }

                ForEach(currentProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Current", point.remaining),
                        series: .value("Series", "Current")
                    )
                    .foregroundStyle(currentColor)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, dash: [7, 3]))
                }

                ForEach(historicalProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Historical", point.remaining),
                        series: .value("Series", "Historical")
                    )
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                }

                RuleMark(x: .value("Now", fetchedAt))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text("Now")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.regularMaterial, in: Capsule())
                    }

                PointMark(
                    x: .value("Now", fetchedAt),
                    y: .value("Remaining now", window.remainingPercent)
                )
                .foregroundStyle(currentColor)
                .symbolSize(55)

                ForEach(visibleCredits) { credit in
                    if let expiresAt = credit.expiresAt {
                        RuleMark(x: .value("Banked reset", expiresAt))
                            .foregroundStyle(
                                Color.orange.opacity(
                                    credit.id == hoveredCredit?.id || credit.id == paceTargetCreditID
                                        ? 0.9
                                        : 0.45
                                )
                            )
                            .lineStyle(StrokeStyle(
                                lineWidth: credit.id == paceTargetCreditID ? 2 : 1,
                                dash: [4, 3]
                            ))
                    }
                }

                if hoveredCredit == nil, let hovered = hoveredPoint {
                    RuleMark(x: .value("Hovered", hovered.date))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))

                    PointMark(
                        x: .value("Hovered", hovered.date),
                        y: .value("Remaining", hovered.remaining)
                    )
                    .foregroundStyle(Color.blue)
                    .symbolSize(55)
                }

                PointMark(
                    x: .value("Reset", paceDeadline),
                    y: .value("Target", 0)
                )
                .foregroundStyle(Color.green)
                .symbolSize(38)

                if let endpoint = currentProjection.last {
                    PointMark(
                        x: .value("Current endpoint", endpoint.date),
                        y: .value("Current endpoint", 0)
                    )
                    .foregroundStyle(currentColor)
                    .symbolSize(32)
                }
            }
            .chartXSelection(value: $selectedDate)
            .onTapGesture {
                if let credit = hoveredCredit {
                    paceTargetCreditID = paceTargetCreditID == credit.id ? "" : credit.id
                }
                // A click pins the chart selection on macOS; release it so the
                // readout follows the pointer again instead of freezing.
                DispatchQueue.main.async { selectedDate = nil }
            }
            .onContinuousHover { phase in
                // chartXSelection does not reliably clear when the pointer
                // leaves the plot, which froze the readout in place.
                if case .ended = phase { selectedDate = nil }
            }
            .chartXScale(domain: window.startsAt ... window.resetsAt)
            .chartYScale(domain: 0 ... 100)
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                    AxisTick(length: 3)
                        .foregroundStyle(Color.secondary)
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            if window.durationMinutes <= 24 * 60 {
                                Text(date, format: .dateTime.hour())
                                    .offset(x: date == window.startsAt ? 8 : date == window.resetsAt ? -8 : 0)
                            } else {
                                Text(date, format: .dateTime.weekday(.abbreviated))
                                    .offset(x: date == window.startsAt ? 8 : date == window.resetsAt ? -8 : 0)
                            }
                        }
                    }
                    .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 25.0, 50.0, 75.0, 100.0]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                        .foregroundStyle(Color.secondary.opacity(0.2))
                    AxisTick(length: 3)
                        .foregroundStyle(Color.secondary)
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text("\(Int(percent))%")
                        }
                    }
                    .foregroundStyle(Color.secondary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 190)
            .padding(.horizontal, 8)
            .accessibilityLabel("Usage forecast")
            .accessibilityValue(
                "Now has \(Int(window.remainingPercent.rounded())) percent remaining. At reset, the current pace leaves \(Int(forecast.expectedRemainingAtReset.rounded())) percent and the historical pace leaves \(Int(forecast.historicalRemainingAtReset.rounded())) percent."
            )
        }
    }

    private func projection(rate: Double, remainingAtReset: Double) -> [BurnPoint] {
        let current = BurnPoint(date: fetchedAt, remaining: window.remainingPercent)
        guard rate > 0 else {
            return [current, BurnPoint(date: paceDeadline, remaining: window.remainingPercent)]
        }
        let exhaustion = fetchedAt.addingTimeInterval(window.remainingPercent / rate * 86_400)
        let endpoint = exhaustion < paceDeadline
            ? BurnPoint(date: exhaustion, remaining: 0)
            : BurnPoint(date: paceDeadline, remaining: remainingAtReset)
        return [current, endpoint]
    }

    private func deduplicated(_ points: [BurnPoint]) -> [BurnPoint] {
        points.sorted { $0.date < $1.date }.reduce(into: []) { result, point in
            if result.last?.date == point.date {
                result[result.count - 1] = point
            } else {
                result.append(point)
            }
        }
    }
}

private struct BurnPoint: Identifiable {
    let date: Date
    let remaining: Double

    var id: Date { date }
}

private struct ChartLegendItem: View {
    let label: String
    let color: Color
    var dash: [CGFloat] = []

    var body: some View {
        HStack(spacing: 4) {
            Canvas { context, size in
                var path = Path()
                path.move(to: CGPoint(x: 0, y: size.height / 2))
                path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, dash: dash))
            }
            .frame(width: 18, height: 8)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @ObservedObject var monitor: UsageMonitor
    @AppStorage(UsageMonitor.safetyBufferKey) private var safetyBuffer = 3.0
    @AppStorage(LoginItem.preferenceKey) private var launchAtLogin = true
    @State private var loginItemError: String?

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
