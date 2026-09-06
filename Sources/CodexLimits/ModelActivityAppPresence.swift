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
        private weak var window: NSWindow?
        private var previousPolicy: NSApplication.ActivationPolicy?

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
            guard previousPolicy == nil else { return }
            previousPolicy = NSApp.activationPolicy()
            NSApp.setActivationPolicy(.regular)
        }

        private func restorePolicy() {
            if let previousPolicy {
                NSApp.setActivationPolicy(previousPolicy)
                self.previousPolicy = nil
            }
        }

        @objc private func windowWillClose(_ notification: Notification) { restorePolicy() }
        @objc private func windowBecameKey(_ notification: Notification) { showInSwitcher() }
        @objc private func windowVisibilityChanged(_ notification: Notification) {
            if window?.isVisible == true { showInSwitcher() }
        }
    }
}
