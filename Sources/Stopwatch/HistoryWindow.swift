import SwiftUI
import AppKit

/// The timing window is AppKit-hosted so it opens reliably. While it is on screen the
/// app also shows a Dock icon; closing the window returns it to menu-bar-only.
final class HistoryWindow: NSObject, NSWindowDelegate {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    private override init() { super.init() }

    func show() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            created.title = "念佛计时"
            created.contentView = NSHostingView(rootView: MainWindow())
            created.isReleasedWhenClosed = false
            created.delegate = self
            if !created.setFrameUsingName("HistoryWindow") {
                created.center()
            }
            created.setFrameAutosaveName("HistoryWindow")
            window = created
        }
        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
