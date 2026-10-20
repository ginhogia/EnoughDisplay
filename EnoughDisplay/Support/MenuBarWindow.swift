import AppKit

/// Closes the MenuBarExtra window the way a user would, by clicking its status item.
///
/// SwiftUI offers no API for this, and ordering the window out by hand leaves the status item thinking it is
/// still open, so the next click would only close it.
@MainActor
enum MenuBarWindow {
    static func toggle() {
        statusButton()?.performClick(nil)
    }

    private static func statusButton() -> NSButton? {
        for window in NSApp.windows where String(describing: type(of: window)) == "NSStatusBarWindow" {
            if let button = window.contentView.flatMap(findButton) { return button }
        }
        return nil
    }

    private static func findButton(in view: NSView) -> NSButton? {
        if let button = view as? NSButton { return button }
        return view.subviews.lazy.compactMap(findButton).first
    }
}
