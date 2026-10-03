import AppKit
import SwiftUI

struct SegmentedControl<Option: Hashable, Label: View>: View {
    let options: [Option]
    let selection: Option?
    var isEnabled: (Option) -> Bool = { _ in true }
    let onSelect: (Option) -> Void
    var onOptionClick: ((Option) -> Void)? = nil
    @ViewBuilder var label: (Option) -> Label
    @Namespace private var selectionAnimation
    @FocusState private var focusedOption: Option?
    @State private var hoveredOption: Option?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    if NSEvent.modifierFlags.contains(.option), let onOptionClick {
                        onOptionClick(option)
                    } else {
                        select(option)
                    }
                } label: {
                    label(option)
                        .font(.system(size: 11, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? .primary : .secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 26)
                        .background { segmentBackground(for: option) }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled(option))
                .focused($focusedOption, equals: option)
                .onHover { hovering in
                    hoveredOption = hovering ? option : nil
                }
                .accessibilityAddTraits(selection == option ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background {
            Capsule()
                .fill(.primary.opacity(0.025))
                .overlay(Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.35 : 0.06), lineWidth: 0.5))
        }
        .onMoveCommand { direction in
            switch direction {
            case .left: moveSelection(by: -1)
            case .right: moveSelection(by: 1)
            default: break
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func segmentBackground(for option: Option) -> some View {
        ZStack {
            if selection == option {
                Capsule()
                    .fill(.primary.opacity(contrast == .increased ? 0.14 : 0.07))
                    .overlay(Capsule().strokeBorder(.primary.opacity(contrast == .increased ? 0.45 : 0.08), lineWidth: 0.5))
                    .matchedGeometryEffect(id: "selection", in: selectionAnimation)
            } else if hoveredOption == option, isEnabled(option) {
                Capsule().fill(.primary.opacity(0.035))
            }
            if focusedOption == option {
                Capsule().strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5)
            }
        }
    }

    private func select(_ option: Option) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            onSelect(option)
        }
    }

    private func moveSelection(by offset: Int) {
        let enabled = options.filter(isEnabled)
        guard let index = focusedOption.flatMap({ enabled.firstIndex(of: $0) })
                ?? selection.flatMap({ enabled.firstIndex(of: $0) }),
              enabled.indices.contains(index + offset) else { return }
        let next = enabled[index + offset]
        focusedOption = next
        select(next)
    }
}
