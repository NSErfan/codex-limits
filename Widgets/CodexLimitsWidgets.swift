import SwiftUI
import WidgetKit

@main
struct CodexLimitsWidgets: WidgetBundle {
    var body: some Widget {
        CombinedWeeklyAllowanceWidget()
        WeeklyPercentageWidget()
        WeeklyGraphWidget()
        ClaudeWeeklyPercentageWidget()
        ClaudeWeeklyGraphWidget()
    }
}
