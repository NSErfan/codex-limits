import AppKit
import SwiftUI

struct ChartRangePicker: View {
    @Binding var selection: ChartRange
    let accent: Color
    var windowHelp = "Window"
    var onOptionClickWindow: (() -> Void)? = nil
    @Namespace private var selectionAnimation

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Button {
                    if range == .window, NSEvent.modifierFlags.contains(.option), let onOptionClickWindow {
                        onOptionClickWindow()
                        return
                    }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
                        selection = range
                    }
                } label: {
                    Text(range.title)
                        .font(.system(size: 11, weight: selection == range ? .semibold : .regular))
                        .foregroundStyle(selection == range ? accent : .secondary)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity)
                        .background {
                            if selection == range {
                                Capsule()
                                    .fill(accent.opacity(0.12))
                                    .overlay(Capsule().strokeBorder(accent.opacity(0.18), lineWidth: 0.5))
                                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(range == .window ? windowHelp : range.title)
                .accessibilityAddTraits(selection == range ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(.primary.opacity(0.03))
                .overlay(Capsule().strokeBorder(.primary.opacity(0.06), lineWidth: 0.5))
        }
    }
}
