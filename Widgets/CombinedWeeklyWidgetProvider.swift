import CodexWidgetKit
import WidgetKit

struct CombinedWeeklyWidgetProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let codex: WeeklyWidgetSnapshot?
        let claude: WeeklyWidgetSnapshot?
        let accent: UsageAccent
    }

    func placeholder(in context: Context) -> Entry {
        preview(at: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(context.isPreview ? preview(at: .now) : reading(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let current = reading(at: .now)
        let dates = WeeklyWidgetTimeline.entryDates(for: [current.codex, current.claude].compactMap { $0 }, at: current.date)
        let entries = dates.map {
            Entry(date: $0, codex: current.codex, claude: current.claude, accent: current.accent)
        }
        completion(Timeline(entries: entries, policy: .after(current.date.addingTimeInterval(15 * 60))))
    }

    private func reading(at date: Date) -> Entry {
        let codex = WeeklyWidgetStore.shared(provider: .codex)
        let claude = WeeklyWidgetStore.shared(provider: .claude)
        return Entry(date: date, codex: codex?.read(), claude: claude?.read(), accent: codex?.readAccent() ?? .automatic)
    }

    private func preview(at date: Date) -> Entry {
        Entry(date: date, codex: .preview(at: date), claude: .preview(at: date, remaining: 42, pace: .slowDown), accent: .automatic)
    }
}
