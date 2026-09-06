import Charts
import SwiftUI

struct ModelActivityScrolling: ViewModifier {
    @ObservedObject var viewport: ModelActivityViewport
    @Binding var selectedDate: Date?

    func body(content: Content) -> some View {
        Group {
            if let duration = viewport.visibleDuration {
                content
                    .chartScrollableAxes(.horizontal)
                    .chartXVisibleDomain(length: duration)
                    .chartScrollPosition(x: $viewport.position)
            } else {
                content
            }
        }
        .onChange(of: viewport.position) { _, _ in
            if selectedDate != nil { selectedDate = nil }
        }
    }
}
