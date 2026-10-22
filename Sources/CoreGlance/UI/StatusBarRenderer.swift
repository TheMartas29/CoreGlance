import AppKit

/// Draws the menu bar item as one image. Normally a template image, so macOS handles
/// light/dark/highlight tinting; when a value must be colored it is drawn in explicit colors.
enum StatusBarRenderer {
    // Fixed sizes chosen to fit the 22–24 pt menu bar, including notched MacBooks.
    private static let valueSize: CGFloat = 11
    private static let captionFont = NSFont.systemFont(ofSize: 7, weight: .semibold)
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
    private static let innerGap: CGFloat = 4
    private static let groupGap: CGFloat = 14

    private static func valueFont(_ style: BarFont, size: CGFloat = valueSize) -> NSFont {
        style == .monospaced ? .monospacedSystemFont(ofSize: size, weight: .regular)
                             : .monospacedDigitSystemFont(ofSize: size, weight: .regular)
    }

    private enum Part {
        case glyph(NSImage)
        case caption(String)
        case value(String, Severity)
        case stacked(String, String)
    }

    private static func temperature(_ r: Reading?, _ prefs: Preferences) -> Double? {
        prefs.temperatureMode == .hottest ? r?.max : r?.average
    }

    /// The metric's value in its threshold unit (%, °C, GB), for coloring.
    static func severity(for metric: Metric, in s: Snapshot, prefs: Preferences) -> Severity {
        switch metric {
        case .memory, .memoryPressure, .compressed:
            // macOS's own memory pressure is the meaningful signal, not a fixed GB figure.
            return s.memory.pressure >= 4 ? .critical : s.memory.pressure >= 2 ? .warning : .normal
        case .cpu: return prefs.severity(metric, value: s.cpu * 100)
        case .gpu: return prefs.severity(metric, value: s.gpu.map { $0 * 100 })
        case .cpuTemperature: return prefs.severity(metric, value: temperature(s.thermals.cpu, prefs))
        case .gpuTemperature: return prefs.severity(metric, value: temperature(s.thermals.gpu, prefs))
        case .batteryTemperature: return prefs.severity(metric, value: s.batteryTemperature)
        case .ssdTemperature: return prefs.severity(metric, value: s.thermals.ssd)
        case .swap: return prefs.severity(metric, value: s.memory.swapUsed / 1_073_741_824)
        case .disk: return prefs.severity(metric, value: s.disk.total > 0 ? s.disk.free / 1e9 : nil)
        case .battery: return prefs.severity(metric, value: s.battery.present && !s.battery.pluggedIn ? s.battery.percent * 100 : nil)
        default: return .normal
        }
    }

    static func value(for metric: Metric, in s: Snapshot, prefs: Preferences) -> String {
        let gb = 1_073_741_824.0
        switch metric {
        case .cpu: return Format.percent(s.cpu)
        case .cpuCores: return ""
        case .cpuFrequency:
            let mhz = s.soc?.pCluster.mhz ?? s.nominalGHz.map { $0 * 1000 }
            return mhz.map { String(format: "%.2fGHz", $0 / 1000) } ?? "–"
        case .eFrequency: return s.soc.map { String(format: "%.2fGHz", $0.eCluster.mhz / 1000) } ?? "–"
        case .gpu: return Format.percent(s.gpu)
        case .gpuFrequency: return s.soc?.gpuMHz.map { "\(Int($0.rounded()))MHz" } ?? "–"
        case .memory:
            return prefs.memoryAsPercent ? Format.percent(s.memory.used / max(s.memory.total, 1))
                                         : String(format: "%.1fG", s.memory.used / gb)
        case .memoryPressure: return s.memory.pressure >= 4 ? "Critical" : s.memory.pressure >= 2 ? "Warn" : "OK"
        case .compressed: return String(format: "%.1fG", s.memory.compressed / gb)
        case .swap: return String(format: "%.1fG", s.memory.swapUsed / gb)
        case .disk: return s.disk.total > 0 ? String(format: "%.0fG", s.disk.free / 1e9) : "–"
        case .cpuTemperature: return Format.temperature(temperature(s.thermals.cpu, prefs))
        case .gpuTemperature: return Format.temperature(temperature(s.thermals.gpu, prefs))
        case .batteryTemperature: return Format.temperature(s.batteryTemperature)
        case .ssdTemperature: return Format.temperature(s.thermals.ssd)
        case .battery: return s.battery.present ? Format.percent(s.battery.percent) : "–"
        case .power:
            let w = s.thermals.systemWatts ?? s.battery.systemPowerIn
            return w.map { String(format: "%.1fW", $0) } ?? "–"
        case .fan:
            let rpm = s.thermals.fans.map(\.rpm).max()
            return rpm.map { "\(Int($0))" } ?? "–"
        case .network: return ""
        }
    }

    private static func parts(for metric: Metric, in s: Snapshot, prefs: Preferences) -> [Part] {
        var parts: [Part] = []
        if prefs.showGlyphs, let image = glyph(metric, s) {
            parts.append(.glyph(image))
            if metric.needsCaption && prefs.showCaptions { parts.append(.caption(metric.caption)) }
        } else if metric != .network {
            parts.append(.caption(metric.caption))
        }
        switch metric {
        case .network:
            parts.append(.stacked("↑" + Format.rate(s.network.up), "↓" + Format.rate(s.network.down)))
        case .cpuCores:
            parts.append(.stacked("P " + Format.percent(s.cpuP), "E " + Format.percent(s.cpuE)))
        default:
            let severity = prefs.colorize ? severity(for: metric, in: s, prefs: prefs) : .normal
            parts.append(.value(value(for: metric, in: s, prefs: prefs), severity))
        }
        return parts
    }

    private static func glyph(_ metric: Metric, _ s: Snapshot) -> NSImage? {
        var name = metric.symbol
        if metric == .battery {
            let p = s.battery.percent
            name = s.battery.charging ? "battery.100percent.bolt"
                : p > 0.87 ? "battery.100percent" : p > 0.62 ? "battery.75percent" : p > 0.37 ? "battery.50percent" : p > 0.12 ? "battery.25percent" : "battery.0percent"
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: metric.title)?.withSymbolConfiguration(symbolConfig)
    }

    private static func size(_ part: Part, _ font: BarFont) -> NSSize {
        switch part {
        case .glyph(let i): return i.size
        case .caption(let t): return (t as NSString).size(withAttributes: [.font: captionFont])
        case .value(let t, _): return (t as NSString).size(withAttributes: [.font: valueFont(font)])
        case .stacked(let a, let b):
            let f = valueFont(font, size: 8.5)
            let sa = (a as NSString).size(withAttributes: [.font: f]), sb = (b as NSString).size(withAttributes: [.font: f])
            return NSSize(width: max(sa.width, sb.width), height: sa.height + sb.height)
        }
    }

    private static func color(_ severity: Severity) -> NSColor? {
        switch severity {
        case .normal: return nil
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// `base` is the color for everything that is not a colored value (black for template images).
    private static func draw(_ part: Part, x: CGFloat, height: CGFloat, font: BarFont, base: NSColor = .black) {
        let sz = size(part, font)
        let y = ((height - sz.height) / 2).rounded()
        switch part {
        case .glyph(let i):
            let rect = NSRect(x: x, y: y, width: sz.width, height: sz.height)
            if base == .black {
                i.draw(in: rect)
            } else {
                // Symbol images draw black; tint them to match the menu bar text.
                NSImage(size: sz, flipped: false) { r in
                    i.draw(in: r); base.set(); r.fill(using: .sourceAtop); return true
                }.draw(in: rect)
            }
        case .caption(let t):
            (t as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: captionFont, .foregroundColor: base])
        case .value(let t, let severity):
            (t as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [.font: valueFont(font), .foregroundColor: color(severity) ?? base])
        case .stacked(let top, let bottom):
            let attrs: [NSAttributedString.Key: Any] = [.font: valueFont(font, size: 8.5), .foregroundColor: base]
            (top as NSString).draw(at: NSPoint(x: x, y: height / 2 - 1), withAttributes: attrs)
            (bottom as NSString).draw(at: NSPoint(x: x, y: height / 2 - sz.height / 2 + 1), withAttributes: attrs)
        }
    }

    /// Horizontal extent of the pixels a part actually paints. SF Symbols and characters
    /// like "°" carry different amounts of built-in side space, so spacing based on their
    /// layout boxes looks uneven; spacing based on ink looks even.
    private static func ink(_ part: Part, height: CGFloat, font: BarFont) -> (minX: CGFloat, width: CGFloat) {
        let sz = size(part, font)
        let scale: CGFloat = 2, pad: CGFloat = 4
        let w = Int(ceil((sz.width + pad * 2) * scale)), h = Int(ceil(height * scale))
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let data = rep.bitmapData else { return (0, sz.width) }
        rep.size = NSSize(width: CGFloat(w) / scale, height: height)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        draw(part, x: pad, height: height, font: font)
        NSGraphicsContext.restoreGraphicsState()

        var minCol = w, maxCol = -1
        for row in 0..<h {
            let line = data + row * rep.bytesPerRow
            for col in 0..<w where line[col * 4 + 3] > 24 {
                minCol = min(minCol, col)
                maxCol = max(maxCol, col)
            }
        }
        guard maxCol >= minCol else { return (0, sz.width) }
        return (CGFloat(minCol) / scale - pad, CGFloat(maxCol - minCol + 1) / scale)
    }

    /// - Parameter dark: whether the menu bar currently shows light text (only used when coloring).
    static func image(for s: Snapshot, prefs: Preferences, dark: Bool = false) -> NSImage? {
        let font = prefs.font
        let height = NSStatusBar.system.thickness
        let groups = prefs.enabled.filter { $0.isAvailable(in: s) }.map { parts(for: $0, in: s, prefs: prefs).map { ($0, ink($0, height: height, font: font)) } }
        guard !groups.isEmpty else { return nil }
        let width = groups.map { g in g.map { $0.1.width }.reduce(0, +) + innerGap * CGFloat(g.count - 1) }.reduce(0, +)
            + groupGap * CGFloat(groups.count - 1)

        let colored = groups.contains { $0.contains { if case .value(_, let sev) = $0.0 { return sev != .normal } else { return false } } }
        let base: NSColor = colored ? (dark ? .white : NSColor(white: 0, alpha: 0.85)) : .black

        // Rendered eagerly into a bitmap. A lazy drawing handler would run inside the status bar's
        // own drawing context, where CoreText can fail to resolve SF Mono and throw (crash in 0.2.0).
        let size = NSSize(width: ceil(width), height: height)
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        var x: CGFloat = 0
        for group in groups {
            for (part, ink) in group {
                draw(part, x: x - ink.minX, height: height, font: font, base: base)
                x += ink.width + innerGap
            }
            x += groupGap - innerGap
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        image.isTemplate = !colored
        return image
    }
}
