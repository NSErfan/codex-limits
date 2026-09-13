import Charts
import SwiftUI

struct CurrentDayHighlight: ChartContent {
    let range: ClosedRange<Date>
    var date: Date = .now

    var body: some ChartContent {
        if let day = Calendar.current.dateInterval(of: .day, for: date) {
            let start = max(day.start, range.lowerBound)
            let end = min(day.end, range.upperBound)
            if start < end {
                RectangleMark(
                    xStart: .value("Today starts", start),
                    xEnd: .value("Today ends", end),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Full", 100)
                )
                .foregroundStyle(Color.green.opacity(0.08))
                .accessibilityLabel("Today")
            }
        }
    }
}
