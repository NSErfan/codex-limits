import SwiftUI

struct ModelActivityRangeNavigation: View {
    @ObservedObject var viewport: ModelActivityViewport
    @Binding var selectedDate: Date?

    var body: some View {
        if let duration = viewport.visibleDuration {
            HStack(spacing: 8) {
                Button {
                    move(by: -duration)
                } label: {
                    Image(systemName: "chevron.left").frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .disabled(viewport.visibleRange.lowerBound <= viewport.range.lowerBound)
                .help("Previous 7 days").accessibilityLabel("Previous 7 days")
                Button {
                    move(by: duration)
                } label: {
                    Image(systemName: "chevron.right").frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .disabled(viewport.visibleRange.upperBound >= viewport.range.upperBound)
                .help("Next 7 days").accessibilityLabel("Next 7 days")
            }
            .buttonStyle(.borderless)
        }
    }

    private func move(by duration: TimeInterval) {
        selectedDate = nil
        let end = max(viewport.range.lowerBound, viewport.range.upperBound.addingTimeInterval(-(viewport.visibleDuration ?? 0)))
        viewport.position = min(max(viewport.position.addingTimeInterval(duration), viewport.range.lowerBound), end)
    }
}
