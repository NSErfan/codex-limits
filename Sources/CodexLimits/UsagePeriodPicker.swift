import CodexWidgetKit
import SwiftUI

struct UsagePeriodPicker: View {
    let snapshot: UsageSnapshot
    let provider: UsageProvider
    let selection: UsagePeriod?
    let now: Date
    let onSelect: (UsagePeriod) -> Void

    var body: some View {
        SegmentedControl(options: UsagePeriod.allCases, selection: selection,
                         isEnabled: { snapshot.limit(for: $0, provider: provider) != nil }, onSelect: onSelect) { period in
            Text(title(for: period))
                .monospacedDigit()
                .accessibilityLabel(details(for: period))
                .help(details(for: period))
        }
        .accessibilityLabel("Usage window")
    }

    private func title(for period: UsagePeriod) -> String {
        guard let window = snapshot.limit(for: period, provider: provider)?.window else {
            return "\(period.title) · Not reported"
        }
        let balance = "\(Int(window.remainingPercent.rounded()))%"
        return "\(period.title) · \(balance)\(window.resetsAt <= now ? " (last)" : " left")"
    }

    private func details(for period: UsagePeriod) -> String {
        guard let window = snapshot.limit(for: period, provider: provider)?.window else {
            return "\(period.title) limit, not reported"
        }
        let balance = Int(window.remainingPercent.rounded())
        let reset = window.resetsAt.formatted(date: .abbreviated, time: .shortened)
        if window.resetsAt <= now {
            return "\(period.title) limit, last reading \(balance) percent, reset passed \(reset), awaiting next reading"
        }
        return "\(period.title) limit, \(balance) percent remaining, resets \(reset)"
    }
}
