import SwiftUI
import AppKit

/// Renders the two surfaces to PNG using the app's own drawing path, so the UI can be
/// verified without Screen Recording permission. Reads records from NIANFO_DATA_DIR.
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
app.appearance = NSAppearance(named: .aqua)

let model = TimerModel.shared
if model.sessions.isEmpty {
    model.seed(SampleData.sessions())
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.temporaryDirectory.path, isDirectory: true)

func render<V: View>(_ view: V, width: CGFloat, to name: String) {
    let hosted = view
        .frame(width: width)
        .background(Color(nsColor: .windowBackgroundColor))
    let hosting = NSHostingView(rootView: hosted)
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 40),
                          styleMask: [.borderless],
                          backing: .buffered,
                          defer: false)
    window.contentView = hosting
    window.displayIfNeeded()
    let size = hosting.fittingSize
    hosting.frame = NSRect(origin: .zero, size: size)
    guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
        FileHandle.standardError.write("no bitmap rep for \(name)\n".data(using: .utf8)!)
        return
    }
    hosting.cacheDisplay(in: hosting.bounds, to: rep)
    let png = rep.representation(using: .png, properties: [:])
    let url = outputDirectory.appendingPathComponent(name)
    do {
        try png?.write(to: url)
        print("wrote \(url.path) (\(Int(size.width))x\(Int(size.height)))")
    } catch {
        print("failed to write \(name): \(error)")
    }
}

// Show both surfaces mid-seat, with taps already logged, so the running state and the
// 一念 counter are visible in the screenshots.
model.start()
for _ in 0..<37 { model.tap() }
Thread.sleep(forTimeInterval: 2)
render(MainWindow(), width: 880, to: "window.png")
render(MenuBarPanel(), width: 300, to: "panel.png")
render(MenuBarLabel(), width: 280, to: "label.png")
