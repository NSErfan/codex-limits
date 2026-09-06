import Foundation

@MainActor
final class ModelActivityStore: ObservableObject {
    @Published private(set) var events: [ModelActivityEvent] = []
    @Published private(set) var models: [String] = []
    @Published private(set) var efforts: [String] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var notice: String?
    @Published private(set) var filesRead = 0
    @Published private(set) var timeline: ModelActivityTimeline
    @Published private(set) var history: HistoryChartData
    @Published private(set) var visibleTimeline: ModelActivityTimeline
    let viewport: ModelActivityViewport
    private var currentWindow: UsageWindow?
    private var samples: [UsageSample] = []
    @Published var days = 7 { didSet { rebuild(resetViewport: true) } }
    @Published var intervalHours = 1.0 { didSet { rebuild() } }
    @Published var metric = ModelActivityTimeline.Metric.total { didSet { rebuild() } }
    @Published var selectedModels: Set<String>? { didSet { rebuild() } }
    @Published var selectedEfforts: Set<String>? { didSet { rebuild() } }

    let home: URL
    private let reader = SessionActivityReader()
    private var anchor: Date

    init(home: URL? = nil, previewEvents: [ModelActivityEvent] = [], now: Date = Date()) {
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"]
        self.home = home ?? configured.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
        anchor = now
        let range = now.addingTimeInterval(-30 * 86_400) ... now
        timeline = ModelActivityTimeline(events: previewEvents, range: range,
                                         intervalDuration: 3_600, metric: .total, models: nil, efforts: nil)
        viewport = ModelActivityViewport(range: range, visibleDuration: 7 * 86_400)
        visibleTimeline = ModelActivityTimeline(events: previewEvents, range: viewport.visibleRange,
                                                intervalDuration: 3_600, metric: .total, models: nil, efforts: nil)
        history = HistoryChartData(samples: [], range: range, bucketDuration: 1_800)
        events = previewEvents
        updateOptions()
        viewport.onRangeChange = { [weak self] _ in self?.rebuildVisibleTimeline() }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let now = Date()
            let snapshot = try await reader.load(home: home, since: now.addingTimeInterval(-30 * 86_400))
            try Task.checkCancellation()
            events = snapshot.events
            filesRead = snapshot.filesRead
            anchor = now
            lastUpdated = now
            notice = !snapshot.folderExists ? "No session folders found at \(home.path)."
                : snapshot.issueCount > 0 ? "Some local records could not be read. Activity coverage may be incomplete." : nil
            updateOptions()
            rebuild()
        } catch is CancellationError { }
        catch { notice = "Local activity could not be read. Try refreshing again." }
    }

    func updateHistory(_ samples: [UsageSample]) {
        guard self.samples != samples else { return }
        self.samples = samples
        history = HistoryChartData(samples: samples, range: timeline.range, bucketDuration: 1_800)
    }

    func matches(_ group: ModelActivityEvent.Group) -> Bool {
        (selectedModels?.contains(group.model) ?? true) && (selectedEfforts?.contains(group.effort) ?? true)
    }

    private func updateOptions() {
        models = Set(events.map(\.group.model)).sorted()
        let order = ["none", "minimal", "low", "medium", "high", "xhigh", "max", "ultra", "unknown"]
        efforts = Set(events.map(\.group.effort)).sorted {
            let lhs = order.firstIndex(of: $0) ?? order.count
            let rhs = order.firstIndex(of: $1) ?? order.count
            return lhs == rhs ? $0 < $1 : lhs < rhs
        }
    }

    func updateWindow(_ window: UsageWindow?) {
        guard currentWindow != window else { return }
        currentWindow = window
        if days == 0 { rebuild(resetViewport: true) }
    }

    func detail(at date: Date?) -> ModelActivityTimeline.Interval {
        var interval = date.flatMap { visibleTimeline.interval(at: $0) } ?? visibleTimeline.summary
        interval.contributions = interval.contributions.filter { matches($0.group) }
        interval.total = interval.matched
        return interval
    }

    private func rebuild(resetViewport: Bool = false) {
        let range: ClosedRange<Date>
        if days == 0, let currentWindow {
            range = currentWindow.startsAt ... currentWindow.resetsAt
        } else {
            range = anchor.addingTimeInterval(-Double(days == 7 ? 30 : max(days, 1)) * 86_400) ... anchor
        }
        let previousRange = timeline.range
        timeline = ModelActivityTimeline(events: events, range: range,
                                         intervalDuration: intervalHours * 3_600, metric: metric,
                                         models: selectedModels, efforts: selectedEfforts)
        viewport.configure(range: range, visibleDuration: days == 7 ? 7 * 86_400 : nil, reset: resetViewport)
        rebuildVisibleTimeline()
        if timeline.range != previousRange {
            history = HistoryChartData(samples: samples, range: timeline.range, bucketDuration: 1_800)
        }
    }

    private func rebuildVisibleTimeline() {
        visibleTimeline = ModelActivityTimeline(events: events, range: viewport.visibleRange,
                                                intervalDuration: intervalHours * 3_600, metric: metric,
                                                models: selectedModels, efforts: selectedEfforts)
    }
}
