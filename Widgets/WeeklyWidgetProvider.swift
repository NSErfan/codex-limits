import CodexWidgetKit
import WidgetKit

struct WeeklyWidgetProvider: TimelineProvider {
    struct Entry: TimelineEntry {
        let date: Date
        let snapshot: WeeklyWidgetSnapshot?
    }

    func placeholder(in context: Context) -> Entry {
        Entry(date: .now, snapshot: .preview())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let snapshot = context.isPreview ? WeeklyWidgetSnapshot.preview() : WeeklyWidgetStore.shared()?.read()
        completion(Entry(date: .now, snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let now = Date()
        let snapshot = WeeklyWidgetStore.shared()?.read()
        var dates = [now]
        if let snapshot {
            // Schedule the transitions themselves so cached readings never imply
            // that an old balance is the new week's balance after a reset.
            let staleAt = snapshot.fetchedAt.addingTimeInterval(WeeklyWidgetSnapshot.staleInterval)
            if staleAt > now { dates.append(staleAt) }
            if let reset = snapshot.window?.resetsAt, reset > now { dates.append(reset) }
        }
        let entries = dates.sorted().map { Entry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(15 * 60))))
    }
}
