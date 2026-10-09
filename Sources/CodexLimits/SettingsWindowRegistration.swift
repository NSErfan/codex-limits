import AppKit
import SwiftUI

struct SettingsWindowRegistration: NSViewRepresentable {
    let presenter: SettingsWindowPresenter

    func makeNSView(context: Context) -> WindowObserver {
        let view = WindowObserver()
        view.presenter = presenter
        return view
    }

    func updateNSView(_ view: WindowObserver, context: Context) { }

    static func dismantleNSView(_ view: WindowObserver, coordinator: ()) {
        view.detach()
    }

    final class WindowObserver: NSView {
        var presenter: SettingsWindowPresenter?
        private weak var attachedWindow: NSWindow?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            if let window {
                attachedWindow = window
                presenter?.attach(window)
            }
        }

        func detach() {
            if let attachedWindow { presenter?.detach(attachedWindow) }
            attachedWindow = nil
        }
    }
}
