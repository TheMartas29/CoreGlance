import AppKit
import SwiftUI

/// `CoreGlance --snapshot <dir>` writes PNGs of the UI with live data (for docs and debugging).
@MainActor
enum Snapshotter {
    static func render(into dir: URL) {
        let monitor = Monitor()
        _ = monitor.diagnostics()  // warms up every sensor
        monitor.start(interval: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        let prefs = Preferences.shared
        save(StatusBarRenderer.image(for: monitor.snapshot, prefs: prefs), dir, "statusbar.png")
        save(view(PopoverView(monitor: monitor, prefs: prefs)), dir, "popover.png")
        save(view(SettingsView(prefs: prefs).padding(14).frame(width: 320)), dir, "settings.png")
    }

    private static func view<V: View>(_ content: V) -> NSImage? {
        let renderer = ImageRenderer(content: content.background(Color.white).environment(\.colorScheme, .light))
        renderer.scale = 2
        return renderer.nsImage
    }

    private static func save(_ image: NSImage?, _ dir: URL, _ name: String) {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}
