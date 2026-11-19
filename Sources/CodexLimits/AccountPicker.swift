import SwiftUI

struct AccountPicker: View {
    @Binding var selection: UsageAccount
    let options: [UsageAccount]

    var body: some View {
        if options.count > 1 {
            SegmentedControl(options: options, selection: selection, onSelect: { selection = $0 }) { account in
                Text(account.displayName)
                    .minimumScaleFactor(0.85)
                    .help("Show \(account.displayName) usage")
            }
            .accessibilityLabel("Usage account")
        }
    }
}
