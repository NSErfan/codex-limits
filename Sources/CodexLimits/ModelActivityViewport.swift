import Foundation

/// Shared chart scrolling stays below the expensive chart builders. Range totals
/// update after scrolling settles, rather than scanning local events per pixel.
@MainActor
final class ModelActivityViewport: ObservableObject {
    @Published private(set) var range: ClosedRange<Date>
    @Published private(set) var visibleDuration: TimeInterval?
    @Published var position: Date {
        didSet {
            guard position != oldValue else { return }
            isScrolling = true
            updateTask?.cancel()
            updateTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 120_000_000) }
                catch { return }
                guard let self else { return }
                self.isScrolling = false
                self.onRangeChange?(self.visibleRange)
            }
        }
    }
    private(set) var isScrolling = false
    var onRangeChange: ((ClosedRange<Date>) -> Void)?
    private var updateTask: Task<Void, Never>?

    init(range: ClosedRange<Date>, visibleDuration: TimeInterval?) {
        self.range = range
        self.visibleDuration = visibleDuration
        position = max(range.lowerBound, range.upperBound.addingTimeInterval(-(visibleDuration ?? 0)))
    }

    var visibleRange: ClosedRange<Date> {
        guard let visibleDuration else { return range }
        let start = min(max(position, range.lowerBound), max(range.lowerBound, range.upperBound.addingTimeInterval(-visibleDuration)))
        return start ... min(start.addingTimeInterval(visibleDuration), range.upperBound)
    }

    func configure(range: ClosedRange<Date>, visibleDuration: TimeInterval?, reset: Bool) {
        guard reset || self.range != range || self.visibleDuration != visibleDuration else { return }
        let wasAtEnd = abs(position.timeIntervalSince(self.range.upperBound.addingTimeInterval(-(self.visibleDuration ?? 0)))) < 1
        self.range = range
        self.visibleDuration = visibleDuration
        let end = max(range.lowerBound, range.upperBound.addingTimeInterval(-(visibleDuration ?? 0)))
        position = reset || wasAtEnd ? end : min(max(position, range.lowerBound), end)
        updateTask?.cancel()
        isScrolling = false
    }

    deinit { updateTask?.cancel() }
}
