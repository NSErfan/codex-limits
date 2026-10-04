import CodexWidgetKit
import SwiftUI

struct ProviderPicker: View {
    @Binding var selection: UsageProvider

    var body: some View {
        SegmentedControl(options: UsageProvider.allCases, selection: selection, onSelect: { selection = $0 }) { provider in
            Text(provider.displayName)
                .help("Show \(provider.displayName) usage")
        }
        .accessibilityLabel("Usage provider")
    }
}
