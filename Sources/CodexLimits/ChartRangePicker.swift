import SwiftUI

struct ChartRangePicker: View {
    @Binding var selection: ChartRange
    var windowTitle = "Current period"
    var windowHelp = "Current period"
    var onOptionClickWindow: (() -> Void)? = nil

    var body: some View {
        SegmentedControl(options: ChartRange.allCases, selection: selection,
                         onSelect: { selection = $0 }, onOptionClick: selectWithOption) { range in
            Text(range == .window ? windowTitle : range.title)
                .help(range == .window ? windowHelp : range.title)
        }
        .accessibilityLabel("Chart range")
    }

    private func selectWithOption(_ range: ChartRange) {
        if range == .window, let onOptionClickWindow {
            onOptionClickWindow()
        } else {
            selection = range
        }
    }
}
