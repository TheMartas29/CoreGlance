import Foundation

enum Format {
    /// Pads with figure spaces (same width as a digit) so the menu bar item does not jitter.
    static func pad(_ s: String, _ width: Int) -> String {
        String(repeating: "\u{2007}", count: max(0, width - s.count)) + s
    }

    static func percent(_ v: Double?, width: Int = 0) -> String {
        guard let v else { return "–" }
        return pad("\(Int((v * 100).rounded()))", width) + "%"
    }

    static func temperature(_ c: Double?, _ unit: TemperatureUnit = Preferences.shared.unit) -> String {
        guard let c else { return "–" }
        let v = unit == .celsius ? c : c * 9 / 5 + 32
        return "\(Int(v.rounded()))°"
    }

    static func ghz(_ mhz: Double?) -> String {
        guard let mhz, mhz > 0 else { return "–" }
        return String(format: "%.2f GHz", mhz / 1000)
    }

    static func mhz(_ mhz: Double?) -> String {
        guard let mhz else { return "–" }
        return "\(Int(mhz.rounded())) MHz"
    }

    static func gigabytes(_ bytes: Double) -> String {
        String(format: "%.1f GB", bytes / 1_073_741_824)
    }

    /// Process memory: "1.2 GB" from 1 GiB up, "340 MB" from 1 MiB, else "12 KB".
    static func bytes(_ bytes: UInt64) -> String {
        let b = Double(bytes)
        if b >= 1_073_741_824 { return String(format: "%.1f GB", b / 1_073_741_824) }
        if b >= 1_048_576 { return String(format: "%.0f MB", b / 1_048_576) }
        return String(format: "%.0f KB", b / 1024)
    }

    static func watts(_ w: Double?) -> String {
        guard let w else { return "–" }
        return w < 10 ? String(format: "%.2f W", w) : String(format: "%.1f W", w)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let units = ["B", "K", "M", "G"]
        var v = bytesPerSecond, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1024; i += 1 }
        return (v < 10 && i > 0 ? String(format: "%.1f", v) : "\(Int(v.rounded()))") + units[i]
    }

    /// Popover "Activity" row: read before write, same separator as the Network row ("↓ x/s  ↑ y/s").
    static func diskActivity(read: Double, write: Double) -> String {
        "R \(rate(read))/s  W \(rate(write))/s"
    }

    static func duration(minutes: Int?) -> String? {
        guard let m = minutes else { return nil }
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
