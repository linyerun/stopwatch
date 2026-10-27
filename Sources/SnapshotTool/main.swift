import SwiftUI
import AppKit

/// Renders every surface to PNG using the app's own drawing path, so the UI can be
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

// Show the surfaces mid-seat, with taps already logged, so the running state and the
// 一念 counter are visible in the screenshots.
model.start()
for _ in 0..<37 { model.tap() }
Thread.sleep(forTimeInterval: 2)

func save<V: View>(_ view: V, name: String, width: CGFloat, height: CGFloat? = nil) {
    guard let image = OffscreenRender.image(of: view, width: width, height: height),
          let png = OffscreenRender.png(image) else {
        print("failed to render \(name)")
        return
    }
    let url = outputDirectory.appendingPathComponent(name)
    try? png.write(to: url)
    print("wrote \(url.path) (\(Int(image.size.width))x\(Int(image.size.height)))")
}

save(MainWindow(), name: "window.png", width: 900, height: 700)
save(RecordsView(), name: "records.png", width: 900, height: 700)
save(MenuBarPanel(), name: "panel.png", width: 300)
save(ExportCardView(sessions: model.sessions).environment(\.colorScheme, .light),
     name: "export.png", width: 760)
