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

    static func duration(minutes: Int?) -> String? {
        guard let m = minutes else { return nil }
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}
