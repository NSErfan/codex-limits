import Foundation

enum HistorySeriesBuilder {
    struct Point: Equatable, Sendable {
        let date: Date
        let remainingPercent: Double
    }

    struct WindowSeries: Equatable, Identifiable, Sendable {
        let resetsAt: Date
        let points: [Point]

        var id: Date { resetsAt }
    }

    static func series(
        from samples: [UsageSample],
        in range: ClosedRange<Date>,
        bucketDuration: TimeInterval
    ) -> [WindowSeries] {
        Dictionary(grouping: samples.filter { range.contains($0.observedAt) }, by: \.resetsAt)
            .map { resetsAt, windowSamples in
                WindowSeries(
                    resetsAt: resetsAt,
                    points: downsampled(
                        windowSamples.sorted { $0.observedAt < $1.observedAt },
                        from: range.lowerBound,
                        bucketDuration: bucketDuration
                    )
                )
            }
            .sorted { $0.resetsAt < $1.resetsAt }
    }

    private static func downsampled(
        _ samples: [UsageSample],
        from start: Date,
        bucketDuration: TimeInterval
    ) -> [Point] {
        guard samples.count > 2, bucketDuration > 0 else {
            return deduplicated(samples)
        }

        var minimumPerBucket: [Int: UsageSample] = [:]
        for sample in samples.dropFirst().dropLast() {
            let bucket = Int(sample.observedAt.timeIntervalSince(start) / bucketDuration)
            if let kept = minimumPerBucket[bucket], kept.remainingPercent <= sample.remainingPercent {
                continue
            }
            minimumPerBucket[bucket] = sample
        }

        let middle = minimumPerBucket.values.sorted { $0.observedAt < $1.observedAt }
        return deduplicated([samples.first!] + middle + [samples.last!])
    }

    private static func deduplicated(_ samples: [UsageSample]) -> [Point] {
        samples.reduce(into: []) { points, sample in
            guard points.last?.date != sample.observedAt else { return }
            points.append(Point(date: sample.observedAt, remainingPercent: sample.remainingPercent))
        }
    }
}
