import CodexWidgetKit
import SwiftUI

/// Shown only when there is more than one provider to choose from.
struct ProviderPicker: View {
    @Binding var selection: UsageProvider
    let options: [UsageProvider]

    var body: some View {
        if options.count > 1 {
            SegmentedControl(options: options, selection: selection, onSelect: { selection = $0 }) { provider in
                Text(provider.displayName)
                    .help("Show \(provider.displayName) usage")
            }
            .accessibilityLabel("Usage provider")
        }
    }
}
