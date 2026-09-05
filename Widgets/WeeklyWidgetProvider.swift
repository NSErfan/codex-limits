import CodexWidgetKit
import WidgetKit

struct WeeklyWidgetProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: WeeklyWidgetSnapshot?
        var accent: UsageAccent = .automatic
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .preview(), accent: WeeklyWidgetStore.shared()?.readAccent() ?? .automatic)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WeeklyWidgetStore.shared()
        let snapshot = context.isPreview ? WeeklyWidgetSnapshot.preview() : store?.read()
        completion(Entry(date: .now, snapshot: snapshot, accent: store?.readAccent() ?? .automatic))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let store = WeeklyWidgetStore.shared()
        let snapshot = store?.read()
        let accent = store?.readAccent() ?? .automatic
        var dates = [now]
        if let snapshot {
            // Schedule the transitions themselves so cached readings never imply
            // that an old balance is the new week's balance after a reset.
            let staleAt = snapshot.fetchedAt.addingTimeInterval(WeeklyWidgetSnapshot.staleInterval)
            if staleAt > now { dates.append(staleAt) }
            if let reset = snapshot.window?.resetsAt, reset > now { dates.append(reset) }
        }
        let entries = dates.sorted().map { Entry(date: $0, snapshot: snapshot, accent: accent) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
