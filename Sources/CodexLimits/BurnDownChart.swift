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
    var isHistorical = false
    var onSelectDate: ((Date) -> Void)? = nil

    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent

    private var accent: Color { UsageChartStyle.accent(for: window.remainingPercent, scheme: colorScheme, selection: usageAccent) }
    private var todayColor: Color { UsageChartStyle.today(scheme: colorScheme) }
    private var creditColor: Color { UsageChartStyle.accent(for: 25, scheme: colorScheme) }

    private var hoveredPoint: BurnPoint? {
        guard let selectedDate else { return nil }
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

    private var observed: [BurnPoint] {
        WindowChartSeries.observed(
            window: window,
            samples: samples,
            tokenHistory: tokenHistory,
            fetchedAt: isHistorical ? min(samples.map(\.observedAt).max() ?? fetchedAt, fetchedAt) : fetchedAt
        )
    }

    private var currentColor: Color {
        forecast.currentPercentPerDay > forecast.historicalPercentPerDay
            ? UsageChartStyle.accent(for: 0, scheme: colorScheme).opacity(0.8)
            : accent.opacity(0.75)
    }

    private var currentProjection: [BurnPoint] {
        WindowChartSeries.projection(
            window: window,
            fetchedAt: fetchedAt,
            deadline: paceDeadline,
            rate: forecast.currentPercentPerDay,
            remainingAtDeadline: forecast.expectedRemainingAtReset
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
                } else if let hovered = hoveredPoint {
                    ChartHoverReadout(
                        title: "\(Int(hovered.remaining.rounded()))% remaining",
                        detail: hovered.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                    )
                } else {
                    ChartLegendItem(label: "Actual", color: accent)
                    ChartLegendItem(label: "Target", color: UsageChartStyle.guide, dash: [3, 4])
                    ChartLegendItem(label: "Current", color: currentColor, dash: [7, 3])
                    if todayRate != nil {
                        ChartLegendItem(label: isHistorical ? "That day" : "Today", color: todayColor, dash: [5, 4])
                    }
                    ChartLegendItem(label: "Historical", color: .secondary.opacity(0.65), dash: [2, 3])
                }
            }
            .frame(height: 40)

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

                ForEach(currentProjection) { point in
                    LineMark(
                        x: .value("Time", point.date),
                        y: .value("Current", point.remaining),
                        series: .value("Series", "Current")
                    )
                    .foregroundStyle(currentColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [7, 3]))
                }

                if isHistorical, let last = observed.last, last.date < fetchedAt {
                    ForEach([last, BurnPoint(date: fetchedAt, remaining: window.remainingPercent)]) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Last known balance", point.remaining),
                                 series: .value("Series", "Last known balance"))
                            .foregroundStyle(accent.opacity(0.45))
                            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
                    }
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
                        Text(isHistorical ? "As of" : "Now")
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

                PointMark(
                    x: .value("Reset", paceDeadline),
                    y: .value("Target", 0)
                )
                .foregroundStyle(UsageChartStyle.guide)
                .symbolSize(22)

                if let endpoint = currentProjection.last {
                    PointMark(
                        x: .value("Current endpoint", endpoint.date),
                        y: .value("Current endpoint", endpoint.remaining)
                    )
                    .foregroundStyle(currentColor)
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
                                        if NSEvent.modifierFlags.contains(.option), let onSelectDate {
                                            if let selectedDate, selectedDate <= fetchedAt { onSelectDate(selectedDate) }
                                            return
                                        }
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
                              date <= fetchedAt else { return }
                        onSelectDate?(date)
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
                "\(isHistorical ? "The selected time" : "Now") has \(Int(window.remainingPercent.rounded())) percent remaining. At reset, the current pace leaves \(Int(forecast.expectedRemainingAtReset.rounded())) percent and the historical pace leaves \(Int(forecast.historicalRemainingAtReset.rounded())) percent."
            )
        }
    }

}
