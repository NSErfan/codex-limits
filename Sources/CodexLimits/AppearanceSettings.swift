import CodexWidgetKit
import Combine
import Foundation

@MainActor
final class AppearanceSettings: ObservableObject {
    static let preferenceKey = "usageAccent"
    static let menuBarDisplayModeKey = "menuBarDisplayMode"
    static let menuBarUsageWindowKey = "menuBarUsageWindow"

    @Published private(set) var accent: UsageAccent
    @Published private(set) var menuBarDisplayMode: MenuBarDisplayMode
    @Published private(set) var widgetError: String?

    @Published private var menuBarUsageWindows: [UsageProvider: MenuBarUsageWindow]

    private let defaults: UserDefaults
    private let widgetStore: WeeklyWidgetStore?
    private let reloadWidgets: () -> Void
    private var reloadTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        widgetStore: WeeklyWidgetStore? = .shared(),
        reloadWidgets: @escaping () -> Void = WeeklyWidgetPublisher.reloadAllTimelines
    ) {
        self.defaults = defaults
        self.widgetStore = widgetStore
        self.reloadWidgets = reloadWidgets
        menuBarDisplayMode = defaults.string(forKey: Self.menuBarDisplayModeKey)
            .flatMap(MenuBarDisplayMode.init(rawValue:)) ?? .iconOnly
        menuBarUsageWindows = Dictionary(uniqueKeysWithValues: UsageProvider.allCases.map { provider in
            let saved = defaults.string(forKey: provider.preferenceKey(Self.menuBarUsageWindowKey))
                .flatMap(MenuBarUsageWindow.init(rawValue:)) ?? .automatic
            let selection = MenuBarUsageWindow.options(for: provider).contains(saved) ? saved : .automatic
            return (provider, selection)
        })
        if let data = defaults.data(forKey: Self.preferenceKey),
           let saved = try? JSONDecoder().decode(UsageAccent.self, from: data), saved.isValid {
            accent = saved
        } else {
            accent = .automatic
        }
        // Also repairs sharing after a previous write failure or an app upgrade.
        if let widgetStore, widgetStore.readAccent() != accent {
            synchronizeWidgets()
        }
    }

    func setAccent(_ selection: UsageAccent) {
        guard selection.isValid, let data = try? JSONEncoder().encode(selection) else { return }
        defaults.set(data, forKey: Self.preferenceKey)
        accent = selection
        synchronizeWidgets()
    }

    func setMenuBarDisplayMode(_ mode: MenuBarDisplayMode) {
        defaults.set(mode.rawValue, forKey: Self.menuBarDisplayModeKey)
        menuBarDisplayMode = mode
    }

    func menuBarUsageWindow(for provider: UsageProvider) -> MenuBarUsageWindow {
        menuBarUsageWindows[provider] ?? .automatic
    }

    func setMenuBarUsageWindow(_ selection: MenuBarUsageWindow, for provider: UsageProvider) {
        guard MenuBarUsageWindow.options(for: provider).contains(selection) else { return }
        defaults.set(selection.rawValue, forKey: provider.preferenceKey(Self.menuBarUsageWindowKey))
        menuBarUsageWindows[provider] = selection
    }

    private func synchronizeWidgets() {
        guard let widgetStore else { return }
        do {
            try widgetStore.writeAccent(accent)
            widgetError = nil
            // The native color picker can emit many changes while dragging.
            // Persist immediately, but request only the settled widget color.
            reloadTask?.cancel()
            let reload = reloadWidgets
            reloadTask = Task {
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                reload()
            }
        } catch {
            widgetError = "Your app color was saved. Widgets couldn’t be updated; select the color again to retry."
        }
    }
}
