import Charts
import SwiftUI

struct ModelActivityPieCharts: View {
    let interval: ModelActivityTimeline.Interval
    let metric: ModelActivityTimeline.Metric
    @Binding var selectedModel: String?
    var isRange = false
    @State private var selectedAngle: Double?
    @Environment(\.colorScheme) private var colorScheme

    private var breakdown: ModelActivityBreakdown {
        ModelActivityBreakdown(contributions: interval.contributions)
    }

    var body: some View {
        let data = breakdown
        VStack(alignment: .leading, spacing: 20) {
            Text("Selected models and efforts in this \(isRange ? "range" : "interval"). Choose a model to see its reasoning efforts.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            HStack(alignment: .top, spacing: 28) {
                pie(title: "Models", slices: data.models, isModel: true)
                Divider()
                if let model = selectedModel, data.models.contains(where: { $0.name == model }) {
                    pie(title: model + " · Efforts", slices: data.efforts(for: model), isModel: false)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.pie").font(.system(size: 32, weight: .light))
                        Text("Choose a model").font(.system(size: 14, weight: .medium))
                        Text("Click a slice or a model below the chart to explore how its tokens were spent.")
                            .font(.system(size: 12)).multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: selectedAngle) { _, angle in
            if let model = ModelActivityBreakdown.slice(at: angle, in: data.models) { selectedModel = model }
        }
        .onChange(of: breakdown.models.map(\.name)) { _, _ in
            selectedAngle = nil
            if !data.models.contains(where: { $0.name == selectedModel }) { selectedModel = nil }
        }
    }

    private func pie(title: String, slices: [ModelActivityBreakdown.Slice], isModel: Bool) -> some View {
        let total = slices.reduce(Int64(0)) { $0 + $1.tokens }
        return VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 14, weight: .semibold)).textSelection(.enabled)
            if total == 0 {
                Text("No \(metric.rawValue.lowercased()) recorded.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 190)
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Tokens", slice.tokens), innerRadius: .ratio(0.62), angularInset: 2)
                        .cornerRadius(3)
                        .foregroundStyle(categoryColor(slice.name, isModel: isModel))
                        .opacity(isModel && selectedModel != nil && selectedModel != slice.name ? 0.55 : 1)
                        .accessibilityLabel(isModel ? slice.name : slice.name.capitalized)
                        .accessibilityValue("\(slice.tokens) tokens, \(share(slice.tokens, total: total))")
                }
                .chartAngleSelection(value: isModel ? $selectedAngle : .constant(nil))
                .chartBackground { _ in
                    VStack(spacing: 4) {
                        Text(total.formatted(.number.notation(.compactName)))
                            .font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit()
                        Text(metric.rawValue.lowercased()).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    .allowsHitTesting(false)
                }
                .frame(height: 190)
            }
            ForEach(slices) { slice in
                if isModel {
                    Button { selectedModel = slice.name; selectedAngle = nil } label: {
                        legend(slice, total: total, isModel: true)
                            .padding(7)
                            .background(.primary.opacity(selectedModel == slice.name ? 0.07 : 0),
                                        in: RoundedRectangle(cornerRadius: 7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(slice.name), \(slice.tokens) tokens, \(share(slice.tokens, total: total)). Show efforts")
                    .accessibilityAddTraits(selectedModel == slice.name ? .isSelected : [])
                } else {
                    legend(slice, total: total, isModel: false).padding(7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func legend(_ slice: ModelActivityBreakdown.Slice, total: Int64, isModel: Bool) -> some View {
        HStack(spacing: 8) {
            Circle().fill(categoryColor(slice.name, isModel: isModel)).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 3) {
                Text(isModel ? slice.name : slice.name.capitalized).font(.system(size: 12, weight: .medium))
                Text("\(slice.tokens.formatted()) tokens").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(share(slice.tokens, total: total)).font(.system(size: 12)).monospacedDigit()
        }
    }

    private func categoryColor(_ name: String, isModel: Bool) -> Color {
        isModel ? ModelActivityColors.model(name, scheme: colorScheme) : ModelActivityColors.effort(name, scheme: colorScheme)
    }

    private func share(_ tokens: Int64, total: Int64) -> String {
        (total > 0 ? Double(tokens) / Double(total) : 0).formatted(.percent.precision(.fractionLength(1)))
    }
}
