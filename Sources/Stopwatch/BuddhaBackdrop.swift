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

/// Deep temple-wall ground behind the photograph plate.
struct BuddhaGround: View {
    var body: some View {
        LinearGradient(stops: [
            .init(color: Color(red: 0.09, green: 0.07, blue: 0.05), location: 0),
            .init(color: Color(red: 0.04, green: 0.03, blue: 0.025), location: 0.55),
            .init(color: Color(red: 0.02, green: 0.015, blue: 0.012), location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .ignoresSafeArea()
    }
}

/// The photograph whole: fitted edge to edge, never cropped, hung like a plate on the
/// wall — hairline frame and shadow so the letterbox reads as intentional matting.
struct BuddhaFit: View {
    var body: some View {
        if let image = BuddhaImage.load() {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .overlay(Rectangle().strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 28, y: 8)
        } else {
            Color.clear
        }
    }
}
