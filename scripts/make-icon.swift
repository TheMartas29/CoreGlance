// Draws the CoreGlance app icon and writes Resources/AppIcon.icns + docs/icon.png.
// Usage: swift scripts/make-icon.swift   (run from the repository root)
import AppKit

func drawIcon(size: CGFloat) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        // macOS icon grid: the rounded square covers ~80% of the canvas.
        let inset = size * 0.1
        let body = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: body, xRadius: size * 0.18, yRadius: size * 0.18)
        NSGraphicsContext.current?.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.01)
        shadow.shadowBlurRadius = size * 0.03
        shadow.set()
        NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1), NSColor(red: 0.20, green: 0.10, blue: 0.32, alpha: 1)])!
            .draw(in: path, angle: -90)
        NSGraphicsContext.current?.restoreGraphicsState()

        // Gauge arc: green -> yellow -> red, like a temperature scale.
        let center = NSPoint(x: rect.midX, y: rect.midY - size * 0.06)
        let radius = size * 0.26
        let colors: [NSColor] = [.systemGreen, .systemYellow, .systemOrange, .systemRed]
        for (i, color) in colors.enumerated() {
            let start = 210 - CGFloat(i) * 60, end = start - 40
            let arc = NSBezierPath()
            arc.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: end, clockwise: true)
            arc.lineWidth = size * 0.07
            arc.lineCapStyle = .round
            color.setStroke()
            arc.stroke()
        }
        // Needle
        let angle = CGFloat(40) * .pi / 180
        let needle = NSBezierPath()
        needle.move(to: center)
        needle.line(to: NSPoint(x: center.x + cos(angle) * radius * 0.85, y: center.y + sin(angle) * radius * 0.85))
        needle.lineWidth = size * 0.035
        needle.lineCapStyle = .round
        NSColor.white.setStroke()
        needle.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - size * 0.04, y: center.y - size * 0.04, width: size * 0.08, height: size * 0.08)).fill()

        // Small chip glyph under the gauge.
        if let chip = NSImage(systemSymbolName: "cpu", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size * 0.12, weight: .medium)) {
            let tinted = NSImage(size: chip.size, flipped: false) { r in
                chip.draw(in: r); NSColor.white.withAlphaComponent(0.85).set(); r.fill(using: .sourceAtop); return true
            }
            tinted.draw(in: NSRect(x: rect.midX - chip.size.width / 2, y: body.minY + size * 0.08, width: chip.size.width, height: chip.size.height))
        }
        return true
    }
}

func writePNG(_ image: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let fm = FileManager.default
let iconset = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fm.removeItem(at: iconset)
try! fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(drawIcon(size: CGFloat(base)), pixels: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(drawIcon(size: CGFloat(base * 2)), pixels: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
writePNG(drawIcon(size: 512), pixels: 512, to: URL(fileURLWithPath: "docs/icon.png"))
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconset.path, "-o", "Resources/AppIcon.icns"]
try! task.run()
task.waitUntilExit()
print(task.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns and docs/icon.png" : "iconutil failed")
