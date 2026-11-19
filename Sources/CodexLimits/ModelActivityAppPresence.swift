import AppKit
import SwiftUI

/// Activity is a regular application window while open. Observe its native close
/// event instead of SwiftUI disappearance, which does not describe minimization.
struct ModelActivityAppPresence: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) { }

    static func dismantleNSView(_ view: WindowObserver, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class WindowObserver: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            // SwiftUI finishes creating the native window before we change policy.
            DispatchQueue.main.async { [weak self, weak window] in
                guard let window else { return }
                self?.coordinator?.attach(window)
            }
        }
    }

    @MainActor final class Coordinator: NSObject {
        // Activation belongs to the app, so a window closing can only restore it after the last one leaves.
        private static var activeCoordinators: Set<ObjectIdentifier> = []
        private static var previousPolicy: NSApplication.ActivationPolicy?
        private weak var window: NSWindow?

        func attach(_ window: NSWindow) {
            guard self.window !== window else { return }
            detach()
            self.window = window
            NotificationCenter.default.addObserver(self, selector: #selector(windowWillClose),
                                                   name: NSWindow.willCloseNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameKey),
                                                   name: NSWindow.didBecomeKeyNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowVisibilityChanged),
                                                   name: NSWindow.didChangeOcclusionStateNotification, object: window)
            showInSwitcher()
            NSApp.activate(ignoringOtherApps: true)
        }

        func detach() {
            NotificationCenter.default.removeObserver(self)
            window = nil
            restorePolicy()
        }

        private func showInSwitcher() {
            guard Self.activeCoordinators.insert(ObjectIdentifier(self)).inserted,
                  Self.activeCoordinators.count == 1 else { return }
            Self.previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }

        private func restorePolicy() {
            guard Self.activeCoordinators.remove(ObjectIdentifier(self)) != nil,
                  Self.activeCoordinators.isEmpty, let previousPolicy = Self.previousPolicy else { return }
            NSApp.setActivationPolicy(previousPolicy)
            Self.previousPolicy = nil
        }

        @objc private func windowWillClose(_ notification: Notification) { restorePolicy() }
        @objc private func windowBecameKey(_ notification: Notification) { showInSwitcher() }
        @objc private func windowVisibilityChanged(_ notification: Notification) {
            if window?.isVisible == true { showInSwitcher() }
        }
    }
}
