import SwiftUI

struct ModelActivityWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            // The content already has a heading. Keep the logical window title
            // for accessibility and the Window menu without crowding the sidebar.
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}
