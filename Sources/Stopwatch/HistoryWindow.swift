import SwiftUI
import AppKit

/// The history window is AppKit-hosted so it opens reliably from an accessory
/// (no Dock icon) app, both on first run and from the menu bar panel.
final class HistoryWindow {
    static let shared = HistoryWindow()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let created = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 880, height: 640),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false)
            created.title = "念佛计时 · 记录"
            created.contentView = NSHostingView(rootView: HistoryView())
            created.isReleasedWhenClosed = false
            if !created.setFrameUsingName("HistoryWindow") {
                created.center()
            }
            created.setFrameAutosaveName("HistoryWindow")
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
