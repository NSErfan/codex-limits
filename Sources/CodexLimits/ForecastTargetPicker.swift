import SwiftUI

struct ForecastTargetPicker: View {
    let window: UsageWindow
    let onCancel: () -> Void
    let onSelect: (Date) -> Void
    let onReset: () -> Void
    @State private var date: Date

    init(window: UsageWindow, initialDate: Date,
         onCancel: @escaping () -> Void, onSelect: @escaping (Date) -> Void,
         onReset: @escaping () -> Void) {
        self.window = window
        self.onCancel = onCancel
        self.onSelect = onSelect
        self.onReset = onReset
        _date = State(initialValue: min(max(initialDate, .now), window.resetsAt))
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Text("Burndown target").font(.headline)
                if context.date < window.resetsAt {
                    DatePicker("Target time", selection: $date,
                               in: context.date ... window.resetsAt,
                               displayedComponents: [.date, .hourAndMinute])
                        .datePickerStyle(.field)
                    Text("\(TimeZone.current.identifier) · Pace your remaining allowance toward a future time before the window resets.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("This window has ended. Refresh usage to choose a new target.")
                        .font(.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Use scheduled reset", action: onReset)
                    Spacer()
                    Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                    Button("Set target") { onSelect(date) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!BurndownTarget.accepts(date, in: window, now: context.date))
                }
            }
            .padding(18)
            .frame(width: 390)
        }
    }
}
