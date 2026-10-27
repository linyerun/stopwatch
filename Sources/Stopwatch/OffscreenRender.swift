import SwiftUI
import AppKit

/// Draws a view offscreen into a bitmap. This is how the export image is produced, and
/// it also backs the snapshot tool, so neither needs screen-recording permission.
enum OffscreenRender {
    static func image<V: View>(of view: V, width: CGFloat, height: CGFloat? = nil) -> NSImage? {
        let sizing: AnyView
        if let height {
            sizing = AnyView(view.frame(width: width, height: height))
        } else {
            sizing = AnyView(view.frame(width: width))
        }
        let hosting = NSHostingView(rootView: sizing)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 40),
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.displayIfNeeded()
        let size = hosting.fittingSize
        guard size.width > 1, size.height > 1,
              let rep = hosting.bitmapImageRepForCachingDisplay(in: NSRect(origin: .zero, size: size))
        else { return nil }
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.cacheDisplay(in: NSRect(origin: .zero, size: size), to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    static func png(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
