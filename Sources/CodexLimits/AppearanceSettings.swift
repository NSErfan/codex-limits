import CodexWidgetKit
import Combine
import Foundation
import WidgetKit

@MainActor
final class AppearanceSettings: ObservableObject {
    static let preferenceKey = "usageAccent"

    @Published private(set) var accent: UsageAccent
    @Published private(set) var widgetError: String?

    private let defaults: UserDefaults
    private let widgetStore: WeeklyWidgetStore?
    private let reloadWidgets: () -> Void
    private var reloadTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        widgetStore: WeeklyWidgetStore? = .shared(),
        reloadWidgets: @escaping () -> Void = {
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.percentageKind)
            WidgetCenter.shared.reloadTimelines(ofKind: WeeklyWidgetStore.graphKind)
        }
    ) {
        self.defaults = defaults
        self.widgetStore = widgetStore
        self.reloadWidgets = reloadWidgets
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
            widgetError = "The app color is saved, but widgets couldn’t be updated. Choose the color again to retry."
        }
    }
}
