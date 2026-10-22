import AppKit

/// Draws the menu bar item as one template image so macOS handles light/dark/highlight tinting.
enum StatusBarRenderer {
    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private static let captionFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
    private static let stackedFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
    private static let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)

    private enum Part {
        case glyph(NSImage)
        case caption(String)
        case value(String)
        case stacked(String, String)
    }

    static func value(for metric: Metric, in s: Snapshot, prefs: Preferences) -> String {
        switch metric {
        case .cpu: return Format.percent(s.cpu, width: 3)
        case .gpu: return Format.percent(s.gpu, width: 3)
        case .cpuFrequency:
            let mhz = s.soc?.pCluster.mhz ?? s.nominalGHz.map { $0 * 1000 }
            return mhz.map { String(format: "%.2f", $0 / 1000) } ?? "–"
        case .memory:
            return prefs.memoryAsPercent ? Format.percent(s.memory.used / max(s.memory.total, 1), width: 3)
                                         : String(format: "%.1fG", s.memory.used / 1_073_741_824)
        case .cpuTemperature: return Format.pad(Format.temperature(s.thermals.cpu?.average), 4)
        case .gpuTemperature: return Format.pad(Format.temperature(s.thermals.gpu?.average), 4)
        case .batteryTemperature: return Format.pad(Format.temperature(s.batteryTemperature), 4)
        case .battery: return s.battery.present ? Format.percent(s.battery.percent, width: 3) : "–"
        case .power:
            let w = s.thermals.systemWatts ?? s.battery.systemPowerIn
            return w.map { String(format: "%.1fW", $0) } ?? "–"
        case .network: return ""
        }
    }

    private static func parts(for metric: Metric, in s: Snapshot, prefs: Preferences) -> [Part] {
        var parts: [Part] = []
        if prefs.showGlyphs, let image = glyph(metric, s) {
            parts.append(.glyph(image))
            let isTemp = [.cpuTemperature, .gpuTemperature].contains(metric)
            if isTemp && prefs.captionTemperatures { parts.append(.caption(metric.caption)) }
            if metric == .cpuFrequency { parts.append(.caption("GHz")) }
        } else if metric != .network {
            parts.append(.caption(metric.caption))
        }
        if metric == .network {
            parts.append(.stacked("↑" + Format.pad(Format.rate(s.network.up), 4), "↓" + Format.pad(Format.rate(s.network.down), 4)))
        } else {
            parts.append(.value(value(for: metric, in: s, prefs: prefs)))
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

    private static func size(_ part: Part) -> NSSize {
        switch part {
        case .glyph(let i): return i.size
        case .caption(let t): return (t as NSString).size(withAttributes: [.font: captionFont])
        case .value(let t): return (t as NSString).size(withAttributes: [.font: valueFont])
        case .stacked(let a, let b):
            let sa = (a as NSString).size(withAttributes: [.font: stackedFont]), sb = (b as NSString).size(withAttributes: [.font: stackedFont])
            return NSSize(width: max(sa.width, sb.width), height: sa.height + sb.height)
        }
    }

    static func image(for s: Snapshot, prefs: Preferences) -> NSImage? {
        let groups = prefs.enabled.map { parts(for: $0, in: s, prefs: prefs) }
        guard !groups.isEmpty else { return nil }
        let height = NSStatusBar.system.thickness
        let innerGap: CGFloat = 2, groupGap: CGFloat = 8
        let width = groups.map { g in g.map { size($0).width }.reduce(0, +) + innerGap * CGFloat(g.count - 1) }.reduce(0, +)
            + groupGap * CGFloat(groups.count - 1)

        let image = NSImage(size: NSSize(width: ceil(width), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for group in groups {
                for part in group {
                    let sz = size(part)
                    switch part {
                    case .glyph(let i):
                        i.draw(in: NSRect(x: x, y: (height - sz.height) / 2, width: sz.width, height: sz.height))
                    case .caption(let t):
                        (t as NSString).draw(at: NSPoint(x: x, y: (height - sz.height) / 2), withAttributes: [.font: captionFont, .foregroundColor: NSColor.black])
                    case .value(let t):
                        (t as NSString).draw(at: NSPoint(x: x, y: (height - sz.height) / 2), withAttributes: [.font: valueFont, .foregroundColor: NSColor.black])
                    case .stacked(let top, let bottom):
                        let attrs: [NSAttributedString.Key: Any] = [.font: stackedFont, .foregroundColor: NSColor.black]
                        let line = sz.height / 2
                        (top as NSString).draw(at: NSPoint(x: x, y: height / 2 - 1), withAttributes: attrs)
                        (bottom as NSString).draw(at: NSPoint(x: x, y: height / 2 - line + 1), withAttributes: attrs)
                    }
                    x += sz.width + innerGap
                }
                x += groupGap - innerGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}
