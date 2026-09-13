import AppKit
import Charts
import CodexWidgetKit
import SwiftUI

struct BurnDownChart: View {
    let window: UsageWindow
    let samples: [UsageSample]
    let tokenHistory: [TokenDay]
    let fetchedAt: Date
    let forecast: Forecast
    let safetyBuffer: Double
    let resetCredits: [ResetCredit]
    let paceDeadline: Date
    @Binding var paceTargetCreditID: String
    var customTargetDate: Date? = nil
    var onSelectTarget: ((Date?) -> Void)? = nil

    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    private var accent: Color { UsageChartStyle.accent(for: window.remainingPercent, scheme: colorScheme, selection: usageAccent) }
    private var todayColor: Color { UsageChartStyle.today(scheme: colorScheme) }
    private var creditColor: Color { UsageChartStyle.accent(for: 25, scheme: colorScheme) }
    private var conservativeColor: Color { UsageChartStyle.accent(for: 0, scheme: colorScheme) }

    private var target: PaceTarget {
        PaceTarget(startsAt: window.startsAt, deadline: paceDeadline, reservePercent: safetyBuffer)
    }

    private var hoveredPoint: BurnPoint? {
        guard let selectedDate, selectedDate <= fetchedAt else { return nil }
        return ChartInteraction.nearest(to: selectedDate, in: observed, date: \.date)
    }

    private var visibleCredits: [ResetCredit] {
        WindowChartSeries.visibleCredits(resetCredits, window: window)
    }

    private var hoveredCredit: ResetCredit? {
        guard let selectedDate else { return nil }
        return credit(near: selectedDate)
    }

    private func credit(near date: Date) -> ResetCredit? {
        ChartInteraction.nearestResetCredit(
            to: date,
            in: visibleCredits,
            window: window
        )
    }

    private func chartDate(
        at location: CGPoint,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) -> Date? {
        guard let plotFrame = proxy.plotFrame else { return nil }
        let frame = geometry[plotFrame]
        guard frame.contains(location) else { return nil }
        return proxy.value(atX: location.x - frame.minX)
    }

    private func toggleCredit(_ credit: ResetCredit) {
        paceTargetCreditID = ChartInteraction.toggledCreditID(
            current: paceTargetCreditID,
            tapped: credit
        )
    }

    private func toggledTargetDate(at date: Date) -> Date? {
        ChartInteraction.toggledTargetDate(
            current: customTargetDate,
            tapped: date,
            visibleSpan: window.resetsAt.timeIntervalSince(window.startsAt)
        )
    }

    private var observed: [BurnPoint] {
        WindowChartSeries.observed(
            window: window,
            samples: samples,
            tokenHistory: tokenHistory,
            fetchedAt: fetchedAt
        )
    }

    private var expectedProjection: [BurnPoint] {
        WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: paceDeadline,
            rate: forecast.currentPercentPerDay,
            remainingAtDeadline: forecast.expectedRemainingAtReset
        )
    }

    private var conservativeProjection: [BurnPoint] {
        WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: paceDeadline,
            rate: forecast.safetyPercentPerDay,
            remainingAtDeadline: forecast.safetyRemainingAtReset
        )
    }

    private var historicalProjection: [BurnPoint] {
        WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: paceDeadline,
            rate: forecast.historicalPercentPerDay,
            remainingAtDeadline: forecast.historicalRemainingAtReset
        )
    }

    private var todayRate: Double? {
        WindowChartSeries.todayRate(
            window: window,
            samples: samples,
            fetchedAt: fetchedAt
        )
    }

    /// Projects today's pace to the window reset, so the endpoint shows
    /// when the limit runs out if the whole week continues like today.
    private var todayProjection: [BurnPoint] {
        guard let rate = todayRate else { return [] }
        let daysLeft = max(window.resetsAt.timeIntervalSince(fetchedAt) / 86_400, 0)
        return WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: window.resetsAt,
            rate: rate,
            remainingAtDeadline: max(window.remainingPercent - rate * daysLeft, 0)
        )
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

    private var nowAnnotationOffset: CGFloat {
        let span = window.resetsAt.timeIntervalSince(window.startsAt)
        guard span > 0 else { return 0 }
        let progress = fetchedAt.timeIntervalSince(window.startsAt) / span
        if progress < 0.08 { return 18 }
        if progress > 0.92 { return -18 }
        return 0
    }

    private var combinesTimeAnnotations: Bool {
        let span = window.resetsAt.timeIntervalSince(window.startsAt)
        return paceTargetCreditID.isEmpty && paceDeadline != window.resetsAt
            && paceDeadline.timeIntervalSince(fetchedAt) < span * 0.08
    }

    var body: some View {
        let accent = self.accent
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let credit = hoveredCredit, let expiresAt = credit.expiresAt {
                    ChartHoverReadout(
                        title: "Banked \(credit.title?.lowercased() ?? "reset")",
                        detail: "Expires \(BankedResetPresentation.dateText(expiresAt))",
                        symbol: "arrow.counterclockwise",
                        hint: credit.id == paceTargetCreditID ? "Click to stop pacing to this reset" : "Click to pace to this reset"
                    )
                } else if let selectedDate, BurndownTarget.accepts(selectedDate, in: window, now: .now) {
                    ChartHoverReadout(
                        title: "Burndown target",
                        detail: selectedDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                        hint: toggledTargetDate(at: selectedDate) == nil
                            ? "Option-click to clear this target"
                            : "Option-click to pace toward this time"
                    )
                } else if let hovered = hoveredPoint {
                    ChartHoverReadout(
                        title: "\(Int(hovered.remaining.rounded()))% remaining",
                        detail: hovered.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                    )
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            ChartLegendItem(label: "Actual", color: accent)
                            ChartLegendItem(label: "Target (\(Int(safetyBuffer.rounded()))%)", color: UsageChartStyle.guide, dash: [3, 4])
                            ChartLegendItem(label: "Expected", color: accent, dash: [7, 3])
                        }
                        GridRow {
                            ChartLegendItem(label: "Conservative", color: conservativeColor, dash: [8, 3, 2, 3])
                            ChartLegendItem(label: "Historical", color: .secondary.opacity(0.65), dash: [2, 3])
                            if todayRate != nil {
                                ChartLegendItem(label: "Today", color: todayColor, dash: [5, 4])
                            }
                        }
                    }
                }
            }
            .frame(height: 40)

            Chart {
                ForEach([
                    BurnPoint(date: target.startsAt, remaining: target.remainingPercent(at: target.startsAt)),
                    BurnPoint(date: target.deadline, remaining: target.remainingPercent(at: target.deadline))
                ]) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Target", point.remaining),
                        series: .value("Series", "Target")
                    )
                    .foregroundStyle(UsageChartStyle.guide)
                    .lineStyle(UsageChartStyle.guideStroke)
                }

                ForEach(observed) { point in
                    AreaMark(
                        x: .value("Time", point.date),
                        yStart: .value("Zero", 0),
                        yEnd: .value("Actual", point.remaining)
                    )
                    .foregroundStyle(UsageChartStyle.area(accent))
                    .interpolationMethod(.linear)
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Actual", point.remaining),
                        series: .value("Series", "Actual")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(UsageChartStyle.actualStroke)
                    .interpolationMethod(.linear)
                }

                ForEach(expectedProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Expected", point.remaining),
                        series: .value("Series", "Expected")
                    )
                    .foregroundStyle(accent)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 3]))
                }

                ForEach(conservativeProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Conservative", point.remaining),
                        series: .value("Series", "Conservative")
                    )
                    .foregroundStyle(conservativeColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [8, 3, 2, 3]))
                }

                ForEach(historicalProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Historical", point.remaining),
                        series: .value("Series", "Historical")
                    )
                    .foregroundStyle(Color.secondary.opacity(0.65))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }

                ForEach(todayProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Today", point.remaining),
                        series: .value("Series", "Today")
                    )
                    .foregroundStyle(todayColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                }

                RuleMark(x: .value("Reference time", fetchedAt))
                    .foregroundStyle(accent.opacity(0.2))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                    .annotation(
                        position: .top,
                        spacing: 2,
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        Text(combinesTimeAnnotations ? "Now · Target" : "Now")
                            .font(UsageChartStyle.axisFont)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.regularMaterial, in: Capsule())
                            .offset(x: nowAnnotationOffset)
                    }

                PointMark(
                    x: .value("Reference time", fetchedAt),
                    y: .value("Balance at reference time", window.remainingPercent)
                )
                .foregroundStyle(accent.opacity(0.15))
                .symbolSize(190)

                PointMark(
                    x: .value("Reference time", fetchedAt),
                    y: .value("Balance at reference time", window.remainingPercent)
                )
                .foregroundStyle(accent)
                .symbolSize(35)

                ForEach(visibleCredits) { credit in
                    if let expiresAt = credit.expiresAt {
                        RuleMark(x: .value("Banked reset", expiresAt))
                            .foregroundStyle(
                                creditColor.opacity(
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
                    .foregroundStyle(accent)
                    .symbolSize(55)
                }

                if paceTargetCreditID.isEmpty, paceDeadline != window.resetsAt {
                    RuleMark(x: .value("Burndown target", paceDeadline))
                        .foregroundStyle(accent.opacity(0.45))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                        .annotation(position: .top, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            if !combinesTimeAnnotations {
                                Text("Target").font(.system(size: 9, weight: .semibold))
                                    .padding(.horizontal, 5).padding(.vertical, 2)
                                    .background(.regularMaterial, in: Capsule())
                            }
                        }
                }

                PointMark(
                    x: .value("Pacing target", target.deadline),
                    y: .value("Target", target.reservePercent)
                )
                .foregroundStyle(UsageChartStyle.guide)
                .symbolSize(22)

                if let endpoint = expectedProjection.last {
                    PointMark(
                        x: .value("Expected endpoint", endpoint.date),
                        y: .value("Expected endpoint", endpoint.remaining)
                    )
                    .foregroundStyle(accent)
                    .symbolSize(32)
                }

                if let endpoint = conservativeProjection.last {
                    PointMark(
                        x: .value("Conservative endpoint", endpoint.date),
                        y: .value("Conservative endpoint", endpoint.remaining)
                    )
                    .foregroundStyle(conservativeColor)
                    .symbolSize(32)
                }

                if let endpoint = todayProjection.last {
                    PointMark(
                        x: .value("Today endpoint", endpoint.date),
                        y: .value("Today endpoint", endpoint.remaining)
                    )
                    .foregroundStyle(todayColor)
                    .symbolSize(32)
                }
            }
            .chartXScale(domain: window.startsAt ... window.resetsAt)
            .chartYScale(domain: 0 ... 100, range: .plotDimension(padding: 6))
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    ZStack(alignment: .topLeading) {
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())

                        if let plotFrame = proxy.plotFrame {
                            let frame = geometry[plotFrame]
                            ForEach(visibleCredits) { credit in
                                if let expiresAt = credit.expiresAt,
                                   let xPosition = proxy.position(forX: expiresAt) {
                                    Button {
                                        if NSEvent.modifierFlags.contains(.option) { return }
                                        selectedDate = nil
                                        toggleCredit(credit)
                                    } label: {
                                        Color.clear
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .frame(width: 14, height: frame.height)
                                    .position(
                                        x: frame.minX + xPosition,
                                        y: frame.midY
                                    )
                                    .accessibilityLabel("Toggle pacing to banked reset")
                                    .accessibilityValue(BankedResetPresentation.dateText(expiresAt))
                                }
                            }
                        }
                    }
                    .simultaneousGesture(SpatialTapGesture().modifiers(.option).onEnded { event in
                        guard let date = chartDate(at: event.location, proxy: proxy, geometry: geometry),
                              BurndownTarget.accepts(date, in: window, now: .now) else { return }
                        selectedDate = nil
                        onSelectTarget?(toggledTargetDate(at: date))
                    })
                    .onContinuousHover { phase in
                        switch phase {
                        case let .active(location):
                            selectedDate = chartDate(
                                at: location,
                                proxy: proxy,
                                geometry: geometry
                            )
                        case .ended:
                            selectedDate = nil
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDates) { value in
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
                    .font(UsageChartStyle.axisFont)
                    .foregroundStyle(Color.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: [0.0, 50.0, 100.0]) { value in
                    AxisGridLine(stroke: UsageChartStyle.gridStroke)
                        .foregroundStyle(UsageChartStyle.grid)
                    AxisValueLabel {
                        if let percent = value.as(Double.self) {
                            Text("\(Int(percent))%")
                        }
                    }
                    .font(UsageChartStyle.axisFont)
                    .foregroundStyle(Color.secondary)
                }
            }
            .chartLegend(.hidden)
            .frame(height: 200)
            .padding(.top, 4)
            .accessibilityLabel("Usage forecast")
            .accessibilityValue(
                "Now has \(Int(window.remainingPercent.rounded())) percent remaining. The target reserves \(Int(safetyBuffer.rounded())) percent. At the pacing target, the expected forecast leaves \(Int(forecast.expectedRemainingAtReset.rounded())) percent, the conservative forecast leaves \(Int(forecast.safetyRemainingAtReset.rounded())) percent, and the historical forecast leaves \(Int(forecast.historicalRemainingAtReset.rounded())) percent."
            )
        }
    }

}
