import Foundation

enum HistorySeriesBuilder {
    struct Point: Equatable, Sendable {
        let date: Date
        let remainingPercent: Double
    }

    struct Run: Equatable, Identifiable, Sendable {
        let id: Int
        let points: [Point]
    }

    struct Connector: Equatable, Identifiable, Sendable {
        let id: Int
        let start: Point
        let end: Point
    }

    struct Series: Equatable, Sendable {
        let runs: [Run]
        let connectors: [Connector]

        var isEmpty: Bool { runs.isEmpty }
        var latestPoint: Point? { runs.last?.points.last }
    }

    static func series(
        from samples: [UsageSample],
        in range: ClosedRange<Date>,
        bucketDuration: TimeInterval,
        maximumSampleGap: TimeInterval = 45 * 60
    ) -> Series {
        let points = deduplicated(
            samples
                .filter { range.contains($0.observedAt) }
                .sorted { $0.observedAt < $1.observedAt }
        )

        var runs: [Run] = []
        var current: [Point] = []
        for point in points {
            if let last = current.last,
               point.date.timeIntervalSince(last.date) > maximumSampleGap {
                runs.append(Run(id: runs.count, points: current))
                current = []
            }
            current.append(point)
        }
        if !current.isEmpty {
            runs.append(Run(id: runs.count, points: current))
        }

        let downsampledRuns = runs.map {
            Run(
                id: $0.id,
                points: downsampled($0.points, from: range.lowerBound, bucketDuration: bucketDuration)
            )
        }
        let connectors = zip(downsampledRuns, downsampledRuns.dropFirst()).map { earlier, later in
            Connector(id: earlier.id, start: earlier.points.last!, end: later.points.first!)
        }
        return Series(runs: downsampledRuns, connectors: connectors)
    }

    private static func downsampled(
        _ points: [Point],
        from start: Date,
        bucketDuration: TimeInterval
    ) -> [Point] {
        guard points.count > 2, bucketDuration > 0 else { return points }

        var minimumPerBucket: [Int: Point] = [:]
        for point in points.dropFirst().dropLast() {
            let bucket = Int(point.date.timeIntervalSince(start) / bucketDuration)
            if let kept = minimumPerBucket[bucket], kept.remainingPercent <= point.remainingPercent {
                continue
            }
            minimumPerBucket[bucket] = point
        }

        let middle = minimumPerBucket.values.sorted { $0.date < $1.date }
        return [points.first!] + middle + [points.last!]
    }

    private static func deduplicated(_ samples: [UsageSample]) -> [Point] {
        samples.reduce(into: []) { points, sample in
            guard points.last?.date != sample.observedAt else { return }
            points.append(Point(date: sample.observedAt, remainingPercent: sample.remainingPercent))
        }
    }
}
