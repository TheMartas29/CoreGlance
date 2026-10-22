import AppKit
import SwiftUI

/// `CoreGlance --snapshot <dir>` writes light and dark PNGs of the menu bar item and the
/// popover with live data. Used for the README screenshots and for debugging.
@MainActor
enum Snapshotter {
    static func render(into dir: URL) {
        let monitor = Monitor()
        _ = monitor.diagnostics()  // warms up every sensor
        monitor.start(interval: 1)
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))

        let prefs = Preferences.shared
        let saved = prefs.enabled
        prefs.enabled = Metric.allCases.filter([.cpu, .cpuFrequency, .cpuTemperature, .gpu, .gpuTemperature, .memory, .batteryTemperature].contains)
        defer { prefs.enabled = saved }

        for dark in [false, true] {
            let bar = StatusBarRenderer.image(for: monitor.snapshot, prefs: prefs, dark: dark)
            save(menuBar(bar, dark: dark), dir, dark ? "menubar-dark.png" : "menubar-light.png")
        }
        for dark in [false, true] {
            let view = PopoverView(monitor: monitor, prefs: prefs, maxHeight: 2000, interactive: false)
                .background(dark ? Color(white: 0.17) : Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .environment(\.colorScheme, dark ? .dark : .light)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            save(renderer.nsImage, dir, dark ? "popover-dark.png" : "popover-light.png")
        }
        renderSettings(monitor, prefs, into: dir)
    }

    /// AppKit-backed controls (checkboxes, steppers) only draw inside a real view hierarchy,
    /// so the settings page is rendered through an off-screen window instead of ImageRenderer.
    static func renderSettings(_ monitor: Monitor, _ prefs: Preferences, into dir: URL) {
        for dark in [false, true] {
            let root = SettingsView(prefs: prefs, snapshot: monitor.snapshot)
                .padding(14)
                .frame(width: 320)
                .background(dark ? Color(white: 0.17) : Color(white: 0.97))
            let host = NSHostingView(rootView: root)
            host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.frame = NSRect(origin: .zero, size: host.fittingSize)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { continue }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent(dark ? "settings-dark.png" : "settings-light.png"))
        }
    }

    /// Puts the template status item on a menu-bar-like strip, tinted for the appearance.
    private static func menuBar(_ item: NSImage?, dark: Bool) -> NSImage? {
        guard let item else { return nil }
        let pad: CGFloat = 12
        let size = NSSize(width: item.size.width + pad * 2, height: item.size.height + 6)
        let scale: CGFloat = 2
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        (dark ? NSColor(white: 0.13, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size), xRadius: 8, yRadius: 8).fill()
        // Template images get tinted like the real menu bar; colored ones are drawn as is.
        let tinted = !item.isTemplate ? item : NSImage(size: item.size, flipped: false) { r in
            item.draw(in: r)
            (dark ? NSColor.white : NSColor.black).set()
            r.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: NSRect(x: pad, y: 3, width: item.size.width, height: item.size.height))
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private static func save(_ image: NSImage?, _ dir: URL, _ name: String) {
        guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }
}
