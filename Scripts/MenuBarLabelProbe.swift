import AppKit
import CodexWidgetKit
import SwiftUI

@main
enum MenuBarLabelProbe {
    @MainActor fileprivate static var configuration: Configuration!

    @MainActor static func main() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.count == 3, arguments[1] == "--cleanup" {
            guard arguments[2] == "MenuBarLabelProbe" || arguments[2].hasPrefix("MenuBarLabelProbe.") else { exit(2) }
            let defaults = UserDefaults(suiteName: arguments[2])
            defaults?.removePersistentDomain(forName: arguments[2])
            defaults?.synchronize()
            return
        }
        do {
            configuration = try Configuration(arguments: arguments)
            try FileManager.default.createDirectory(at: configuration.output, withIntermediateDirectories: true)
            MenuBarLabelProbeApp.main()
        } catch {
            reportFailure(error, arguments: arguments)
            exit(1)
        }
    }

    private static func reportFailure(_ error: Error, arguments: [String]) {
        let result = "FAIL: \(error.localizedDescription)\n"
        FileHandle.standardError.write(Data(result.utf8))
        let outputIndex = arguments.dropFirst().first == "--live-snapshot" ? 4 : 3
        guard arguments.count > outputIndex else { return }
        let output = URL(fileURLWithPath: arguments[outputIndex], isDirectory: true)
        try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try? result.write(to: output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8)
    }
}

private struct MenuBarLabelProbeApp: App {
    @NSApplicationDelegateAdaptor(Delegate.self) private var delegate
    @StateObject private var monitor: UsageMonitor
    @StateObject private var appearance: AppearanceSettings
    private let configuration: Configuration

    init() {
        let configuration = MenuBarLabelProbe.configuration!
        let defaults = UserDefaults(suiteName: configuration.suiteName)!
        if configuration.phase != .read {
            defaults.removePersistentDomain(forName: configuration.suiteName)
        }
        let snapshot = configuration.snapshot
        let state = State(snapshot: snapshot, samples: [], previousStatus: nil)
        defaults.set(try! JSONEncoder().encode(state), forKey: configuration.provider.preferenceKey("usageState"))
        let appearance = AppearanceSettings(defaults: defaults, widgetStore: nil, reloadWidgets: {})
        if configuration.phase != .read {
            appearance.setMenuBarUsageWindow(configuration.initialSelection, for: configuration.provider)
        }
        self.configuration = configuration
        _appearance = StateObject(wrappedValue: appearance)
        _monitor = StateObject(wrappedValue: UsageMonitor(
            provider: configuration.provider, defaults: defaults, historyDirectory: configuration.output,
            widgetStore: WeeklyWidgetStore(
                directory: configuration.output.appendingPathComponent("widget"), provider: configuration.provider
            ),
            fetchResult: {
                if let snapshot { return .fetched(snapshot) }
                throw ProbeError.usageUnavailable
            },
            startsAutomatically: false
        ))
        delegate.configuration = configuration
        delegate.appearance = appearance
        delegate.defaults = defaults
    }

    var body: some Scene {
        MenuBarExtra {
            Text(configuration.liveCache == nil ? "Synthetic label validation" : "Saved usage label validation")
        } label: {
            ProviderMenuLabel(
                monitor: monitor,
                displayMode: configuration.displayMode,
                usageWindow: appearance.menuBarUsageWindow(for: configuration.provider)
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct State: Encodable {
    let snapshot: UsageSnapshot?
    let samples: [UsageSample]
    let previousStatus: PaceStatus?
}

private enum ProbeError: LocalizedError {
    case usageUnavailable
    case invalidArguments
    case isolatedSuiteRequired
    case savedUsageMissing
    case invalidSavedUsage

    var errorDescription: String? {
        switch self {
        case .usageUnavailable: "Usage is unavailable."
        case .invalidArguments:
            "Usage: MenuBarLabelProbe provider displayMode output [usageWindow] [scenario] [suiteName] [phase], or --live-snapshot provider displayMode output isolatedSuite sequence|write|read commaSeparatedWindows [sourceDomain]."
        case .isolatedSuiteRequired: "Verification requires a MenuBarLabelProbe preference suite."
        case .savedUsageMissing: "The installed app has no saved usage snapshot for this provider."
        case .invalidSavedUsage: "The installed app's saved usage snapshot could not be used safely."
        }
    }
}

fileprivate struct Configuration {
    enum Scenario: String {
        case complete, fiveHourLowest, missingFiveHour, missingWeekly, unavailable
    }

    enum Phase: String {
        case single, switching, write, read
    }

    let provider: UsageProvider
    let displayMode: MenuBarDisplayMode
    let output: URL
    let selection: MenuBarUsageWindow
    let scenario: Scenario
    let suiteName: String
    let phase: Phase
    let liveCache: LiveCache?
    private let requestedSelections: [MenuBarUsageWindow]?

    init(arguments: [String]) throws {
        if arguments.dropFirst().first == "--live-snapshot" {
            self = try Self(liveArguments: arguments)
            return
        }
        guard arguments.count >= 4,
              let provider = UsageProvider(rawValue: arguments[1]),
              let displayMode = MenuBarDisplayMode(rawValue: arguments[2]) else {
            throw ProbeError.invalidArguments
        }
        self.provider = provider
        self.displayMode = displayMode
        output = URL(fileURLWithPath: arguments[3], isDirectory: true)
        selection = arguments.count > 4 ? MenuBarUsageWindow(rawValue: arguments[4])! : .automatic
        scenario = arguments.count > 5 ? Scenario(rawValue: arguments[5])! : .complete
        suiteName = arguments.count > 6 ? arguments[6] : "MenuBarLabelProbe"
        guard suiteName == "MenuBarLabelProbe" || suiteName.hasPrefix("MenuBarLabelProbe.") else {
            throw ProbeError.isolatedSuiteRequired
        }
        phase = arguments.count > 7 ? Phase(rawValue: arguments[7])! : .single
        liveCache = nil
        requestedSelections = nil
    }

    private init(liveArguments arguments: [String]) throws {
        guard arguments.count >= 8,
              let provider = UsageProvider(rawValue: arguments[2]),
              let displayMode = MenuBarDisplayMode(rawValue: arguments[3]) else { throw ProbeError.invalidArguments }
        let requested = arguments[7].split(separator: ",").compactMap { MenuBarUsageWindow(rawValue: String($0)) }
        guard !requested.isEmpty,
              requested.count == arguments[7].split(separator: ",").count,
              requested.allSatisfy({ MenuBarUsageWindow.options(for: provider).contains($0) }) else {
            throw ProbeError.invalidArguments
        }
        switch arguments[6] {
        case "sequence": phase = .switching
        case "write" where requested.count == 1: phase = .write
        case "read" where requested.count == 1: phase = .read
        default: throw ProbeError.invalidArguments
        }
        guard arguments[5].hasPrefix("MenuBarLabelProbe.") else { throw ProbeError.isolatedSuiteRequired }
        self.provider = provider
        self.displayMode = displayMode
        output = URL(fileURLWithPath: arguments[4], isDirectory: true)
        suiteName = arguments[5]
        selection = requested.last!
        requestedSelections = requested
        scenario = .complete
        let sourceDomain = arguments.count > 8 ? arguments[8] : "com.github.nserfan.CodexLimits"
        liveCache = try LiveCache.read(provider: provider, domain: sourceDomain)
    }

    var initialSelection: MenuBarUsageWindow { phase == .switching ? selections[0] : selection }

    var selections: [MenuBarUsageWindow] {
        if let requestedSelections { return requestedSelections }
        return phase == .switching ? [.automatic, .fiveHour, .weekly, .fiveHour, .automatic, .weekly] : [selection]
    }

    var snapshot: UsageSnapshot? {
        if let liveCache { return liveCache.snapshot }
        guard scenario != .unavailable else { return nil }
        if provider == .copilot {
            return snapshot(main: reading(period: .monthly, remaining: 46), others: [])
        }
        let fiveHour = reading(period: .fiveHour, remaining: scenario == .fiveHourLowest ? 23 : 81)
        let weekly = reading(period: .weekly, remaining: scenario == .fiveHourLowest ? 68 : 46)
        let modelWeekly = LimitReading(
            limitId: "\(provider.rawValue)-scoped-model", name: "Scoped weekly",
            window: weekly.window.withRemainingPercent(5)
        )
        switch scenario {
        case .complete:
            return snapshot(main: weekly, others: [modelWeekly, fiveHour])
        case .fiveHourLowest:
            return snapshot(main: fiveHour, others: [modelWeekly, weekly])
        case .missingFiveHour:
            return snapshot(main: weekly, others: [modelWeekly])
        case .missingWeekly:
            return snapshot(main: fiveHour, others: [modelWeekly])
        case .unavailable:
            return nil
        }
    }

    func expectedPercent(for selection: MenuBarUsageWindow) -> Int? {
        if let liveCache { return liveCache.expectedPercent(for: selection) }
        guard scenario != .unavailable else { return nil }
        if provider == .copilot { return 46 }
        switch selection {
        case .automatic:
            return scenario == .fiveHourLowest ? 23 : scenario == .missingWeekly ? 81 : 46
        case .fiveHour:
            return scenario == .missingFiveHour ? nil : scenario == .fiveHourLowest ? 23 : 81
        case .weekly:
            return scenario == .missingWeekly ? nil : scenario == .fiveHourLowest ? 68 : 46
        }
    }

    func expectedTitle(for selection: MenuBarUsageWindow) -> String {
        let percentage = expectedPercent(for: selection).map { "\($0)%" } ?? "—"
        let prefix: String
        switch selection {
        case .automatic: prefix = ""
        case .fiveHour: prefix = provider == .copilot ? "" : "5h "
        case .weekly: prefix = provider == .copilot ? "" : "Week "
        }
        let usage = "\(prefix)\(percentage)"
        return displayMode == .iconOnly ? usage : "\(provider.displayName) \(usage)"
    }

    func expectedDescription(for selection: MenuBarUsageWindow) -> String {
        let window = provider != .copilot && selection != .automatic ? "\(selection.title) " : ""
        let reading = expectedPercent(for: selection).map { "\($0)% remaining" } ?? "usage unavailable"
        return "\(provider.displayName): \(window)\(reading)"
    }

    private func reading(period: UsagePeriod, remaining: Double) -> LimitReading {
        LimitReading(
            limitId: provider.rawValue, name: period.title,
            window: .init(
                remainingPercent: remaining,
                resetsAt: Date().addingTimeInterval(Double(period.durationMinutes) * 60),
                durationMinutes: period.durationMinutes
            )
        )
    }

    private func snapshot(main: LimitReading, others: [LimitReading]) -> UsageSnapshot {
        UsageSnapshot(mainLimit: main, otherLimits: others, tokenHistory: [], resetCredits: [], fetchedAt: Date())
    }
}

fileprivate struct LiveCache {
    let snapshot: UsageSnapshot
    let observedAt: Date

    static func read(provider: UsageProvider, domain: String) throws -> Self {
        guard let defaults = UserDefaults(suiteName: domain),
              let data = defaults.persistentDomain(forName: domain)?[provider.preferenceKey("usageState")] as? Data else {
            throw ProbeError.savedUsageMissing
        }
        guard data.count <= 4_000_000,
              let state = try? JSONDecoder().decode(CachedState.self, from: data),
              let saved = state.snapshot else { throw ProbeError.invalidSavedUsage }
        let main = try sanitized(saved.mainLimit, provider: provider)
        let others = saved.otherLimits.compactMap { try? sanitized($0, provider: provider) }
        return Self(
            snapshot: UsageSnapshot(
                mainLimit: main, otherLimits: others, tokenHistory: [], resetCredits: [], fetchedAt: saved.fetchedAt
            ),
            observedAt: Date()
        )
    }

    var summary: [String] {
        let formatter = ISO8601DateFormatter()
        return [
            "source: installed cached usage; no refresh",
            "fetchedAt: \(formatter.string(from: snapshot.fetchedAt))",
            "observedAt: \(formatter.string(from: observedAt))",
            "cachedAgeSeconds: \(Int(observedAt.timeIntervalSince(snapshot.fetchedAt)))"
        ] + ([snapshot.mainLimit] + snapshot.otherLimits).map {
            "cached reading: \($0.name); remainingPercent: \($0.window.remainingPercent); durationMinutes: \($0.window.durationMinutes); resetInSeconds: \(Int($0.window.resetsAt.timeIntervalSince(observedAt)))"
        }
    }

    func availabilitySummary(for selections: [MenuBarUsageWindow]) -> [String] {
        var lines: [String] = []
        if snapshot.fetchedAt > observedAt { lines.append("cache limitation: fetchedAt is in the future") }
        for selection in Set(selections.map(\.rawValue)).sorted().compactMap(MenuBarUsageWindow.init(rawValue:)) {
            guard selection != .automatic else { continue }
            guard let reading = reading(for: selection) else {
                lines.append("cached \(selection.title): missing; expecting an unavailable label")
                continue
            }
            if reading.window.resetsAt <= observedAt || reading.window.resetsAt < snapshot.fetchedAt {
                lines.append("cache limitation: the cached \(selection.title) window reset has passed")
            }
        }
        return lines
    }

    func expectedPercent(for selection: MenuBarUsageWindow) -> Int? {
        guard let reading = reading(for: selection),
              selection == .automatic || snapshot.fetchedAt <= reading.window.resetsAt else { return nil }
        return Int(reading.window.remainingPercent.rounded())
    }

    private func reading(for selection: MenuBarUsageWindow) -> LimitReading? {
        switch selection {
        case .automatic: snapshot.mainLimit
        case .fiveHour:
            ([snapshot.mainLimit] + snapshot.otherLimits).first { $0.window.durationMinutes == 300 }
        case .weekly:
            ([snapshot.mainLimit] + snapshot.otherLimits).first { $0.window.durationMinutes == 10_080 }
        }
    }

    private static func sanitized(_ reading: LimitReading, provider: UsageProvider) throws -> LimitReading {
        guard reading.limitId == provider.rawValue,
              let period = provider.periods.first(where: { $0.includes(durationMinutes: reading.window.durationMinutes) }),
              reading.window.remainingPercent.isFinite,
              (0 ... 100).contains(reading.window.remainingPercent) else { throw ProbeError.invalidSavedUsage }
        // Live cache data stays in memory until account details and model-scoped readings are removed.
        return LimitReading(limitId: provider.rawValue, name: period.title, window: reading.window)
    }

    private struct CachedState: Decodable {
        let snapshot: UsageSnapshot?
    }
}

private extension UsageWindow {
    func withRemainingPercent(_ value: Double) -> Self {
        Self(remainingPercent: value, resetsAt: resetsAt, durationMinutes: durationMinutes)
    }
}

@MainActor
private final class Delegate: NSObject, NSApplicationDelegate {
    var configuration: Configuration!
    var appearance: AppearanceSettings!
    var defaults: UserDefaults!

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await verify() }
    }

    private func verify() async {
        var lines = configuration.liveCache?.summary ?? []
        lines.append(contentsOf: configuration.liveCache?.availabilitySummary(for: configuration.selections) ?? [])
        var failures: [String] = []
        for (index, selection) in configuration.selections.enumerated() {
            if configuration.phase == .switching {
                appearance.setMenuBarUsageWindow(selection, for: configuration.provider)
            }
            lines.append("step: \(index + 1); selection: \(selection.rawValue)")
            lines.append("expected title: \(configuration.expectedTitle(for: selection)); expected tooltip: \(configuration.expectedDescription(for: selection))")
            if appearance.menuBarUsageWindow(for: configuration.provider) != selection {
                failures.append("preference did not read \(selection.rawValue)")
            }
            let button = await settledButton(for: selection)
            guard let button else {
                failures.append("native status button was not found")
                continue
            }
            record(button, step: index + 1, lines: &lines)
            failures.append(contentsOf: mismatches(button, selection: selection))
        }
        if configuration.phase == .write || configuration.liveCache != nil { defaults.synchronize() }
        lines.append(contentsOf: failures.map { "FAIL: \($0)" })
        if failures.isEmpty {
            let source = configuration.liveCache == nil ? configuration.scenario.rawValue : "liveCache"
            lines.append("PASS: \(configuration.provider.rawValue) \(configuration.displayMode.rawValue) \(configuration.selection.rawValue) \(source) \(configuration.phase.rawValue)")
        }
        try! lines.joined(separator: "\n").write(
            to: configuration.output.appendingPathComponent("result.txt"), atomically: true, encoding: .utf8
        )
        if failures.isEmpty { NSApp.terminate(nil) } else { exit(1) }
    }

    private func settledButton(for selection: MenuBarUsageWindow) async -> NSStatusBarButton? {
        var lastButton: NSStatusBarButton?
        // SwiftUI updates the native status item on a later run-loop turn.
        for _ in 0 ..< 40 {
            try? await Task.sleep(for: .milliseconds(125))
            if let button = statusButton() {
                lastButton = button
                if mismatches(button, selection: selection).isEmpty { return button }
            }
        }
        return lastButton
    }

    private func statusButton() -> NSStatusBarButton? {
        NSApp.windows.compactMap(\.contentView).compactMap(statusButton(in:)).first
    }

    private func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton { return button }
        return view.subviews.compactMap(statusButton(in:)).first
    }

    private func mismatches(_ button: NSStatusBarButton, selection: MenuBarUsageWindow) -> [String] {
        var failures: [String] = []
        let expectedTitle = configuration.expectedTitle(for: selection)
        let expectedDescription = configuration.expectedDescription(for: selection)
        if button.title != expectedTitle {
            failures.append("\(selection.rawValue) title expected \(expectedTitle), got \(button.title)")
        }
        // Some macOS versions extract only the label's title and image from MenuBarExtra.
        // The visible fixed-window prefix identifies the selection even without native help.
        if let tooltip = button.toolTip, tooltip != expectedDescription {
            failures.append("\(selection.rawValue) tooltip expected \(expectedDescription), got \(tooltip)")
        }
        if configuration.displayMode == .textOnly {
            if button.image != nil { failures.append("text-only label unexpectedly has an image") }
        } else if button.image?.size != NSSize(width: 25, height: 18) {
            failures.append("provider image is missing or has an unexpected size")
        }
        return failures
    }

    private func record(_ button: NSStatusBarButton, step: Int, lines: inout [String]) {
        lines.append("button title: \(button.title); image: \(String(describing: button.image?.size)); frame: \(button.frame)")
        lines.append("tooltip: \(button.toolTip ?? "nil")")
        lines.append("accessibility: \(button.accessibilityLabel() ?? "nil")")
        if let cell = button.cell {
            lines.append("imageRect: \(cell.imageRect(forBounds: button.bounds)); titleRect: \(cell.titleRect(forBounds: button.bounds))")
        }
        if let bitmap = button.bitmapImageRepForCachingDisplay(in: button.bounds) {
            button.cacheDisplay(in: button.bounds, to: bitmap)
            let png = bitmap.representation(using: .png, properties: [:])!
            try! png.write(to: configuration.output.appendingPathComponent("button-\(step).png"))
            try! png.write(to: configuration.output.appendingPathComponent("button.png"))
        }
    }
}
