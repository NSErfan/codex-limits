import CodexWidgetKit
import SwiftUI

@MainActor
struct ModelActivityView: View {
    @StateObject private var store: ModelActivityStore
    @State private var selectedDate: Date?
    @State private var showsBreakdown = false
    @State private var selectedModel: String?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.usageAccent) private var usageAccent
    private let loadsAutomatically: Bool
    private let samples: [UsageSample]
    private let window: UsageWindow?

    init(store: ModelActivityStore? = nil, loadsAutomatically: Bool = true, samples: [UsageSample] = [], window: UsageWindow? = nil) {
        _store = StateObject(wrappedValue: store ?? ModelActivityStore())
        self.loadsAutomatically = loadsAutomatically
        self.samples = samples
        self.window = window
    }

    private var accent: Color { usageAccent.readableColor(scheme: colorScheme) }

    var body: some View {
        HStack(spacing: 0) {
            filters
            Divider()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    HStack(spacing: 28) {
                        statistic("Matching tokens", value: store.visibleTimeline.matched.formatted(.number.notation(.compactName)))
                        statistic("Share of recorded tokens", value: share(store.visibleTimeline.matched, of: store.visibleTimeline.total))
                        statistic("Intervals matched", value: "\(store.visibleTimeline.matchingIntervals) / \(store.visibleTimeline.activeIntervals)")
                        Spacer()
                    }
                    ModelActivityBurnDownChart(history: store.history, timeline: store.timeline,
                                               viewport: store.viewport, accent: accent, selectedDate: $selectedDate)
                    HStack {
                        Picker("Activity view", selection: $showsBreakdown) {
                            Text("Timeline").tag(false)
                            Text("Token breakdown").tag(true)
                        }
                        .pickerStyle(.segmented).labelsHidden().frame(width: 270)
                        Spacer()
                        Picker("Interval", selection: $store.intervalHours) {
                            Text("30 minutes").tag(0.5)
                            Text("1 hour").tag(1.0)
                            Text("6 hours").tag(6.0)
                            Text("1 day").tag(24.0)
                        }
                        .frame(width: 160)
                    }
                }
                .padding(26)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if !showsBreakdown {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text("Selected models · Colors match the sidebar")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                    Spacer()
                                }
                                ModelActivityChart(timeline: store.timeline, visibleTimeline: store.visibleTimeline,
                                                   viewport: store.viewport, selectedDate: $selectedDate)
                                Text("Hover an interval to inspect it. Move away to see the whole visible range.")
                                    .font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                        }
                        intervalDetails
                        coverage
                    }
                    .padding(26)
                }
            }
        }
        .frame(minWidth: 940, minHeight: 680)
        .tint(accent)
        .background(Color(nsColor: .windowBackgroundColor))
        .modifier(ModelActivityWindowTitle())
        .task {
            guard loadsAutomatically else { return }
            while !Task.isCancelled {
                await store.refresh()
                do { try await Task.sleep(nanoseconds: 60_000_000_000) }
                catch { break }
            }
        }
        .onChange(of: window, initial: true) { _, window in store.updateWindow(window) }
        .onChange(of: samples, initial: true) { _, samples in store.updateHistory(samples) }
        .onChange(of: store.days) { _, _ in selectedDate = nil }
        .onChange(of: store.intervalHours) { _, _ in selectedDate = nil }
    }

    private var filters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("FILTER ACTIVITY")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(1.2)
                    Text("Choose models and efforts for the graphs and breakdown.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                filterSection("Models", options: store.models, selection: $store.selectedModels)
                filterSection("Reasoning effort", options: store.efforts, selection: $store.selectedEfforts, capitalized: true)
                Button("Reset filters") {
                    store.selectedModels = nil
                    store.selectedEfforts = nil
                }
                .buttonStyle(.borderless)
            }
            .padding(18)
        }
        .frame(width: 210)
        .background(.primary.opacity(0.025))
    }

    private func filterSection(_ title: String, options: [String], selection: Binding<Set<String>?>,
                               capitalized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text(title).font(.system(size: 12, weight: .semibold))
            HStack(spacing: 12) {
                Button("Select all") { selection.wrappedValue = nil }
                    .accessibilityLabel("Select all \(title.lowercased())")
                Button("Deselect all") { selection.wrappedValue = [] }
                    .accessibilityLabel("Deselect all \(title.lowercased())")
            }
            .buttonStyle(.borderless).font(.system(size: 11))
            if options.isEmpty {
                Text(store.isLoading ? "Reading local logs…" : "No recorded activity")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            ForEach(options, id: \.self) { option in
                Toggle(isOn: Binding(
                    get: { selection.wrappedValue?.contains(option) ?? true },
                    set: { enabled in
                        var selected = selection.wrappedValue ?? Set(options)
                        if enabled { selected.insert(option) } else { selected.remove(option) }
                        selection.wrappedValue = selected
                    }
                )) {
                    HStack(spacing: 7) {
                        Circle().fill(capitalized ? ModelActivityColors.effort(option, scheme: colorScheme)
                                      : ModelActivityColors.model(option, scheme: colorScheme))
                            .frame(width: 7, height: 7)
                        Text(capitalized ? option.capitalized : option)
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .help(option)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Model activity").font(.system(size: 26, weight: .medium, design: .rounded))
                Spacer()
                Group {
                    if store.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        refreshButton
                    }
                }
                .frame(width: 28, height: 28)
                Picker("Period", selection: $store.days) {
                    Text("Window").tag(0).disabled(window == nil)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 220)
            }
            HStack {
                Text("Model and effort contribution to recorded local token activity.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Spacer()
                Picker("Count", selection: $store.metric) {
                    ForEach(ModelActivityTimeline.Metric.allCases) { metric in
                        Text(metric.rawValue).tag(metric)
                    }
                }
                .labelsHidden().frame(width: 135)
                // Match the segmented control's visible edge inside its native frame.
                .padding(.trailing, 5)
            }
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 13, weight: .medium))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help("Refresh activity")
        .accessibilityLabel("Refresh activity")
        .disabled(store.isLoading || !loadsAutomatically)
    }

    @ViewBuilder private var intervalDetails: some View {
        let interval = store.detail(at: selectedDate)
        Group {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(selectedDate == nil ? "Visible range" : "Selected interval")
                        .font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Text(interval.start.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                         + " – " + interval.end.formatted(.dateTime.month(.abbreviated).day().hour().minute()))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                if interval.contributions.isEmpty {
                    Text(selectedDate == nil ? "No activity matches the filters in this range." : "No activity matches the filters in this interval.")
                        .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 75)
                } else if showsBreakdown {
                    ModelActivityPieCharts(interval: interval, metric: store.metric, selectedModel: $selectedModel, isRange: selectedDate == nil)
                } else {
                    HStack {
                        Text("MODEL / EFFORT")
                        Spacer()
                        Text(store.metric.rawValue.uppercased()).frame(width: 110, alignment: .trailing)
                        Text("SHARE").frame(width: 65, alignment: .trailing)
                    }
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                    ForEach(interval.contributions) { contribution in
                        HStack(spacing: 12) {
                            Circle().fill(ModelActivityColors.model(contribution.group.model, scheme: colorScheme))
                                .frame(width: 6, height: 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(contribution.group.model).font(.system(size: 12, weight: .medium))
                                HStack(spacing: 5) {
                                    Circle().fill(ModelActivityColors.effort(contribution.group.effort, scheme: colorScheme))
                                        .frame(width: 5, height: 5)
                                    Text("\(contribution.group.effort.capitalized) effort · \(contribution.events) usage \(contribution.events == 1 ? "event" : "events")")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(contribution.tokens, format: .number).monospacedDigit()
                                .frame(width: 110, alignment: .trailing)
                            Text(share(contribution.tokens, of: interval.total)).monospacedDigit()
                                .frame(width: 65, alignment: .trailing)
                        }
                        .font(.system(size: 12))
                        .padding(.vertical, 7)
                        .foregroundStyle(store.matches(contribution.group) ? Color.primary : Color.secondary)
                    }
                }
            }
        }
    }

    private var coverage: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let notice = store.notice {
                Label(notice, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.secondary)
            }
            Text("Local records only · Token share is not account-limit share. Total tokens include cached inputs; output tokens include reasoning output. Other devices and missing logs are not covered.")
                .foregroundStyle(.secondary)
            HStack {
                Text("\(store.filesRead) session files")
                if let updated = store.lastUpdated {
                    Text("· Updated \(updated.formatted(date: .omitted, time: .shortened))")
                }
            }
            .foregroundStyle(.tertiary)
        }
        .font(.system(size: 11))
        .fixedSize(horizontal: false, vertical: true)
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func share(_ part: Int64, of total: Int64) -> String {
        (total > 0 ? Double(part) / Double(total) : 0).formatted(.percent.precision(.fractionLength(1)))
    }
}
