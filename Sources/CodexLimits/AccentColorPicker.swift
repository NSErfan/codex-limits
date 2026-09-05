import AppKit
import CodexWidgetKit
import SwiftUI

struct AccentColorPicker: View {
    @ObservedObject var appearance: AppearanceSettings
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accent color")
                Spacer()
                Text(appearance.accent.name).foregroundStyle(.secondary)
            }
            HStack(spacing: 9) {
                ForEach(UsageAccent.presets, id: \.name) { preset in
                    Button { appearance.setAccent(preset) } label: {
                        Circle()
                            .fill(preset.color(scheme: scheme))
                            .overlay {
                                if preset == .automatic {
                                    Image(systemName: "a.circle")
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(scheme == .dark ? .black.opacity(0.75) : .white)
                                }
                            }
                            .padding(4)
                            .overlay {
                                Circle().strokeBorder(
                                    appearance.accent == preset ? preset.color(scheme: scheme) : .clear,
                                    lineWidth: 1.5
                                )
                            }
                            .frame(width: 32, height: 32)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(preset.name)
                    .accessibilityLabel(preset.name)
                    .accessibilityAddTraits(appearance.accent == preset ? .isSelected : [])
                }
            }
            ColorPicker("Custom color", selection: Binding(
                get: { appearance.accent.color(scheme: scheme) },
                set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    appearance.setAccent(.custom(
                        red: min(1, max(0, Double(rgb.redComponent))),
                        green: min(1, max(0, Double(rgb.greenComponent))),
                        blue: min(1, max(0, Double(rgb.blueComponent)))
                    ))
                }
            ), supportsOpacity: false)
            Text("Applies to the app, graphs, and both widgets. Automatic changes color with your remaining balance.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Text and graph colors adjust for readability while keeping your chosen background tint.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error = appearance.widgetError {
                Text(error).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
