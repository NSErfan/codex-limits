import SwiftUI

struct ForecastDatePicker: View {
    let samples: [UsageSample]
    let safetyBuffer: Double
    let now: Date
    let onCancel: () -> Void
    let onSelect: (HistoricalForecastSelection) -> Void
    @State private var selection: HistoricalForecastSelection

    init(samples: [UsageSample], safetyBuffer: Double,
         initialSelection: HistoricalForecastSelection, now: Date,
         onCancel: @escaping () -> Void, onSelect: @escaping (HistoricalForecastSelection) -> Void) {
        self.samples = samples
        self.safetyBuffer = safetyBuffer
        self.now = now
        self.onCancel = onCancel
        self.onSelect = onSelect
        var selection = initialSelection
        selection.date = min(selection.date, now)
        _selection = State(initialValue: selection)
    }

    var body: some View {
        let result = HistoricalForecast.reconstruct(at: selection.date, samples: samples,
            legacyDurationMinutes: selection.legacyDurationMinutes, safetyBuffer: safetyBuffer, now: now)
        let canShowForecast = if case .success = result { true } else { false }
        VStack(alignment: .leading, spacing: 14) {
            Text("Choose a past time").font(.headline)
            DatePicker("As of", selection: $selection.date, in: ...now, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.field)
            Text("\(TimeZone.current.identifier) · Uses only readings available by this time.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            switch result {
            case let .success(value):
                if value.assumedDuration { durationPicker }
                Text("Last reading: \(value.lastReading.observedAt.formatted(date: .abbreviated, time: .shortened)) · \(Int(value.window.remainingPercent.rounded()))% remaining")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            case let .failure(reason):
                if reason == .invalidLegacyWindow { durationPicker }
                Text(reason.localizedDescription).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Show forecast") { onSelect(selection) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canShowForecast)
            }
        }
        .padding(18)
        .frame(width: 360)
    }

    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Window length", selection: $selection.legacyDurationMinutes) {
                Text("7 days").tag(10_080)
                Text("5 hours").tag(300)
            }
            Text("Older readings did not save the window length. Choose the limit that was active then.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

}
