import Foundation

public enum WeeklyWidgetTimeline {
    public static func entryDates(for snapshots: [WeeklyWidgetSnapshot], at date: Date) -> [Date] {
        var dates: Set<Date> = [date]
        for snapshot in snapshots {
            let staleAt = snapshot.fetchedAt.addingTimeInterval(WeeklyWidgetSnapshot.staleInterval)
            if staleAt > date { dates.insert(staleAt) }
            if let reset = snapshot.window?.resetsAt, reset > date { dates.insert(reset) }
            for offset in stride(from: 300.0, to: WeeklyWidgetSnapshot.staleInterval, by: 300) {
                let update = date.addingTimeInterval(offset)
                if update < staleAt, update < (snapshot.window?.resetsAt ?? date) {
                    dates.insert(update)
                }
            }
        }
        return dates.sorted()
    }
}
