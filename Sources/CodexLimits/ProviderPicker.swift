import CodexWidgetKit
import SwiftUI

struct ProviderPicker: View {
    @Binding var selection: UsageProvider

    var body: some View {
        Picker("Usage provider", selection: $selection) {
            ForEach(UsageProvider.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Usage provider")
    }
}
