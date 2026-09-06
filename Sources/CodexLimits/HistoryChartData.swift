import Foundation

/// Prepared once when chart inputs change, not while scrolling or hovering.
struct HistoryChartData {
    enum Selection: Equatable {
        case point(HistorySeriesBuilder.Point)
        case reset(Date)
        case estimated(HistorySeriesBuilder.Point)
    }

    struct AreaPoint {
        let baseline = 0.0
        let date: Date
        let remainingPercent: Double
        let seriesID: String
    }

    let linePoints: [HistorySeriesBuilder.Point]
    let sampledArea: [AreaPoint]
    let gapArea: [AreaPoint]
    let series: HistorySeriesBuilder.Series
    let plotRuns: [HistorySeriesBuilder.Run]
    private let points: [HistorySeriesBuilder.Point]

    init(samples: [UsageSample], range: ClosedRange<Date>, bucketDuration: TimeInterval) {
        series = HistorySeriesBuilder.series(from: samples, in: range, bucketDuration: bucketDuration)
        points = series.runs.flatMap(\.points)
        let runs = series.runs.map { HistorySeriesBuilder.Run(id: $0.id, points: Self.simplified($0.points)) }
        plotRuns = runs
        linePoints = runs.flatMap(\.points)
        sampledArea = runs.flatMap { run in
            run.points.map { AreaPoint(date: $0.date, remainingPercent: $0.remainingPercent, seriesID: "run-\(run.id)") }
        }
        gapArea = series.connectors.flatMap { connector in
            [connector.start, connector.end].map {
                AreaPoint(date: $0.date, remainingPercent: $0.remainingPercent, seriesID: "gap-\(connector.id)")
            }
        }
    }

    func selection(at date: Date?, visibleSpan: TimeInterval) -> Selection? {
        guard let date else { return nil }
        if let reset = ChartInteraction.nearest(to: date, in: series.resets, visibleSpan: visibleSpan, date: { $0 }) {
            return .reset(reset)
        }
        if let gap = series.connectors.first(where: { date > $0.start.date && date < $0.end.date }) {
            // Match the straight connector drawn between the surrounding samples.
            let fraction = date.timeIntervalSince(gap.start.date) / gap.end.date.timeIntervalSince(gap.start.date)
            let remaining = gap.start.remainingPercent + fraction * (gap.end.remainingPercent - gap.start.remainingPercent)
            return .estimated(.init(date: date, remainingPercent: remaining))
        }
        // Keep every prepared reading available to hover, including points
        // omitted from the drawing because they lie on a straight segment.
        var lower = 0
        var upper = points.count
        while lower < upper {
            let middle = (lower + upper) / 2
            if points[middle].date < date { lower = middle + 1 } else { upper = middle }
        }
        guard !points.isEmpty else { return nil }
        if lower == 0 { return .point(points[0]) }
        if lower == points.count { return .point(points[lower - 1]) }
        let before = points[lower - 1]
        let after = points[lower]
        return .point(date.timeIntervalSince(before.date) <= after.date.timeIntervalSince(date) ? before : after)
    }

    static func simplified(_ points: [HistorySeriesBuilder.Point]) -> [HistorySeriesBuilder.Point] {
        var result: [HistorySeriesBuilder.Point] = []
        result.reserveCapacity(points.count)
        for point in points {
            while result.count >= 2 {
                let first = result[result.count - 2]
                let middle = result[result.count - 1]
                let span = point.date.timeIntervalSince(first.date)
                guard span > 0 else { break }
                let fraction = middle.date.timeIntervalSince(first.date) / span
                let interpolated = first.remainingPercent + (point.remainingPercent - first.remainingPercent) * fraction
                guard abs(interpolated - middle.remainingPercent) < 1e-9 else { break }
                result.removeLast()
            }
            result.append(point)
        }
        return result
    }
}
