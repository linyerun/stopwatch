import SwiftUI
import AppKit

/// Loads Assets/amitabha.png from the app bundle, or from the source tree when running
/// unpackaged (the snapshot and test tools are bare binaries).
enum BuddhaImage {
    static let name = "amitabha"

    static func load() -> CGImage? {
        for url in candidateURLs() {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
            return image
        }
        return nil
    }

    private static func candidateURLs() -> [URL] {
        var urls: [URL] = []
        if let inBundle = Bundle.main.url(forResource: name, withExtension: "png") {
            urls.append(inBundle)
        }
        if let resources = Bundle.main.resourceURL {
            urls.append(resources.appendingPathComponent("Assets/\(name).png"))
        }
        urls.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Assets/\(name).png"))
        // Bare binaries (self-test, snapshots) run from the project root; this covers
        // being launched from somewhere else inside the source tree.
        let sourceRoot = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()   // Sources/Stopwatch
            .deletingLastPathComponent()   // Sources
            .deletingLastPathComponent()   // project root
        urls.append(sourceRoot.appendingPathComponent("Assets/\(name).png"))
        return urls
    }
}

/// Full-bleed 阿弥陀佛 backdrop with a dimming gradient so the white readout stays legible.
struct BuddhaBackdrop: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = BuddhaImage.load() {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                        // Oversize, then lift the figure so the readout has the floor to
                        // itself without exposing a gap at the bottom.
                        .frame(width: geometry.size.width, height: geometry.size.height * 1.18)
                        .offset(y: -geometry.size.height * 0.09)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                } else {
                    LinearGradient(colors: [Color(red: 0.10, green: 0.07, blue: 0.05),
                                            Color(red: 0.02, green: 0.02, blue: 0.03)],
                                   startPoint: .top, endPoint: .bottom)
                }
                LinearGradient(stops: [
                    .init(color: Color.black.opacity(0.45), location: 0),
                    .init(color: Color.black.opacity(0.10), location: 0.40),
                    .init(color: Color.black.opacity(0.78), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
        }
        .ignoresSafeArea()
    }
}
