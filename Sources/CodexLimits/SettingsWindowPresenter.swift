import AppKit

@MainActor
final class SettingsWindowPresenter {
    private weak var window: NSWindow?
    private var isPresentationRequested = false
    private let activateApplication: @MainActor () -> Void

    init(activateApplication: @escaping @MainActor () -> Void = { NSApp.activate(ignoringOtherApps: true) }) {
        self.activateApplication = activateApplication
    }

    func open(using openSettings: () -> Void) {
        isPresentationRequested = true
        if let window { configure(window) }
        openSettings()
        schedulePresentation()
    }

    func attach(_ window: NSWindow) {
        self.window = window
        configure(window)
        schedulePresentation()
    }

    func detach(_ window: NSWindow) {
        guard self.window === window else { return }
        self.window = nil
    }

    private func configure(_ window: NSWindow) {
        window.collectionBehavior.remove(.canJoinAllSpaces)
        window.collectionBehavior.insert(.moveToActiveSpace)
    }

    private func schedulePresentation() {
        guard isPresentationRequested else { return }
        DispatchQueue.main.async { [weak self] in
            self?.presentIfRequested()
        }
    }

    private func presentIfRequested() {
        guard isPresentationRequested, let window else { return }
        isPresentationRequested = false
        configure(window)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        activateApplication()
    }
}
