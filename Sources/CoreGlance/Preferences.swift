import Foundation
import ServiceManagement

enum MetricGroup: String, CaseIterable {
    case cpu = "CPU", gpu = "GPU", memory = "Memory", disk = "Disk", battery = "Battery", system = "System", network = "Network"
}

/// Everything that can be shown in the menu bar, in menu bar order: all values of one
/// component sit next to each other (CPU usage, clocks and temperature, then GPU, …).
enum Metric: String, CaseIterable, Identifiable {
    case cpu, cpuCores, cpuFrequency, eFrequency, cpuTemperature
    case gpu, gpuFrequency, gpuTemperature
    case memory, memoryPressure, compressed, swap
    case disk, ssdTemperature
    case battery, batteryTemperature
    case power, fan
    case network

    var id: String { rawValue }

    var group: MetricGroup {
        switch self {
        case .cpu, .cpuCores, .cpuFrequency, .eFrequency, .cpuTemperature: return .cpu
        case .gpu, .gpuFrequency, .gpuTemperature: return .gpu
        case .memory, .memoryPressure, .compressed, .swap: return .memory
        case .disk, .ssdTemperature: return .disk
        case .battery, .batteryTemperature: return .battery
        case .power, .fan: return .system
        case .network: return .network
        }
    }

    var title: String {
        switch self {
        case .cpu: return "CPU usage"
        case .cpuCores: return "P-core / E-core usage"
        case .cpuFrequency: return "P-core frequency"
        case .eFrequency: return "E-core frequency"
        case .gpu: return "GPU usage"
        case .gpuFrequency: return "GPU frequency"
        case .memory: return "Memory used"
        case .memoryPressure: return "Memory pressure"
        case .compressed: return "Compressed memory"
        case .swap: return "Swap used"
        case .disk: return "Free disk space"
        case .cpuTemperature: return "CPU temperature"
        case .gpuTemperature: return "GPU temperature"
        case .batteryTemperature: return "Battery temperature"
        case .ssdTemperature: return "SSD temperature"
        case .battery: return "Battery charge"
        case .power: return "System power"
        case .fan: return "Fan speed"
        case .network: return "Network speed"
        }
    }

    /// SF Symbol shown next to the value in the menu bar.
    var symbol: String {
        switch self {
        case .cpu, .cpuTemperature: return "cpu"
        case .cpuCores: return "square.split.2x1"
        case .cpuFrequency, .eFrequency: return "speedometer"
        case .gpu, .gpuTemperature: return "cube.transparent"
        case .gpuFrequency: return "cube"
        case .memory: return "memorychip"
        case .memoryPressure: return "gauge.with.dots.needle.50percent"
        case .compressed: return "rectangle.compress.vertical"
        case .swap: return "arrow.left.arrow.right"
        case .disk, .ssdTemperature: return "internaldrive"
        case .batteryTemperature: return "minus.plus.batteryblock"
        case .battery: return "battery.75percent"
        case .power: return "bolt"
        case .fan: return "fan"
        case .network: return "arrow.up.arrow.down"
        }
    }

    /// Tiny label next to the glyph where the glyph alone would be ambiguous,
    /// or instead of the glyph when glyphs are turned off.
    var caption: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuCores: return "P/E"
        case .cpuFrequency: return "P GHz"
        case .eFrequency: return "E"
        case .gpu: return "GPU"
        case .gpuFrequency: return "GPU MHz"
        case .memory: return "RAM"
        case .memoryPressure: return "PRES"
        case .compressed: return "ZIP"
        case .swap: return "SWAP"
        case .disk: return "DISK"
        case .cpuTemperature: return "CPU"
        case .gpuTemperature: return "GPU"
        case .batteryTemperature: return "BAT"
        case .ssdTemperature: return "SSD"
        case .battery: return "BAT"
        case .power: return "PWR"
        case .fan: return "FAN"
        case .network: return "NET"
        }
    }

    /// Whether the caption is drawn even when glyphs are on (the glyph is shared or unclear).
    var needsCaption: Bool {
        // Temperatures share the glyph of their component; the "°" tells them apart.
        [.eFrequency, .swap, .compressed].contains(self)
    }
}

enum Severity { case normal, warning, critical }

/// Level at which a value turns orange (warning) and red (critical).
/// For `lowerIsWorse` metrics (free disk, battery charge) the value is bad *below* the level.
struct Threshold: Equatable {
    var warning: Double
    var critical: Double
}

extension Metric {
    /// Defaults from vendor documentation and field reports; see RESEARCH.md ("Alert thresholds").
    /// Memory metrics use macOS's own memory pressure instead and are not listed here.
    var defaultThreshold: Threshold? {
        switch self {
        case .cpu, .gpu: return Threshold(warning: 80, critical: 95)                // % busy
        case .cpuTemperature: return Threshold(warning: 90, critical: 100)          // °C, M-series TjMax ≈ 100
        case .gpuTemperature: return Threshold(warning: 85, critical: 100)
        case .batteryTemperature: return Threshold(warning: 40, critical: 44)       // charging pauses ≈ 44 °C
        case .ssdTemperature: return Threshold(warning: 70, critical: 80)           // typical NVMe WCTEMP/CCTEMP
        case .swap: return Threshold(warning: 4, critical: 10)                      // GB
        case .disk: return Threshold(warning: 50, critical: 20)                     // GB free
        case .battery: return Threshold(warning: 20, critical: 10)                  // % charge
        default: return nil
        }
    }

    var lowerIsWorse: Bool { self == .disk || self == .battery }

    var isTemperature: Bool { [.cpuTemperature, .gpuTemperature, .batteryTemperature, .ssdTemperature].contains(self) }

    /// Unit of the threshold values (temperatures are stored in °C).
    var thresholdUnit: String {
        switch self {
        case .swap, .disk: return "GB"
        case .cpuTemperature, .gpuTemperature, .batteryTemperature, .ssdTemperature: return "°C"
        default: return "%"
        }
    }

    var thresholdRange: ClosedRange<Double> {
        switch self {
        case .disk: return 0...1000
        case .swap: return 0...128
        case .cpuTemperature, .gpuTemperature, .batteryTemperature, .ssdTemperature: return 20...130
        default: return 0...100
        }
    }
}

enum TemperatureUnit: String, CaseIterable { case celsius, fahrenheit }
enum TemperatureMode: String, CaseIterable { case average, hottest }
enum BarFont: String, CaseIterable { case system, monospaced }

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var enabled: [Metric] { didSet { defaults.set(enabled.map(\.rawValue), forKey: "metrics") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var showGlyphs: Bool { didSet { defaults.set(showGlyphs, forKey: "showGlyphs") } }
    @Published var showCaptions: Bool { didSet { defaults.set(showCaptions, forKey: "captionTemperatures") } }
    @Published var memoryAsPercent: Bool { didSet { defaults.set(memoryAsPercent, forKey: "memoryAsPercent") } }
    @Published var unit: TemperatureUnit { didSet { defaults.set(unit.rawValue, forKey: "unit") } }
    @Published var temperatureMode: TemperatureMode { didSet { defaults.set(temperatureMode.rawValue, forKey: "temperatureMode") } }
    @Published var font: BarFont { didSet { defaults.set(font.rawValue, forKey: "font") } }
    @Published var colorize: Bool { didSet { defaults.set(colorize, forKey: "colorize") } }
    /// User overrides of the default thresholds.
    @Published var customThresholds: [Metric: Threshold] {
        didSet {
            let plain = Dictionary(uniqueKeysWithValues: customThresholds.map { ($0.key.rawValue, [$0.value.warning, $0.value.critical]) })
            defaults.set(plain, forKey: "thresholds")
        }
    }

    private init() {
        let stored = defaults.stringArray(forKey: "metrics")?.compactMap(Metric.init(rawValue:))
        let initial = stored ?? [.cpu, .cpuTemperature, .gpu, .memory, .batteryTemperature]
        // Saved lists from older versions may be in a different order; always use the catalogue order.
        enabled = Metric.allCases.filter(initial.contains)
        interval = defaults.object(forKey: "interval") as? Double ?? 2
        showGlyphs = defaults.object(forKey: "showGlyphs") as? Bool ?? true
        showCaptions = defaults.object(forKey: "captionTemperatures") as? Bool ?? true
        memoryAsPercent = defaults.bool(forKey: "memoryAsPercent")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .celsius
        temperatureMode = TemperatureMode(rawValue: defaults.string(forKey: "temperatureMode") ?? "") ?? .average
        font = BarFont(rawValue: defaults.string(forKey: "font") ?? "") ?? .system
        colorize = defaults.object(forKey: "colorize") as? Bool ?? true
        let plain = defaults.dictionary(forKey: "thresholds") as? [String: [Double]] ?? [:]
        customThresholds = plain.reduce(into: [:]) { result, item in
            if let m = Metric(rawValue: item.key), item.value.count == 2 { result[m] = Threshold(warning: item.value[0], critical: item.value[1]) }
        }
    }

    func isEnabled(_ m: Metric) -> Bool { enabled.contains(m) }

    func threshold(_ m: Metric) -> Threshold? { customThresholds[m] ?? m.defaultThreshold }

    func setThreshold(_ m: Metric, _ t: Threshold) { customThresholds[m] = t == m.defaultThreshold ? nil : t }

    func resetThresholds() { customThresholds = [:] }

    /// Classifies a value (in the threshold's unit) against the user's or default levels.
    func severity(_ m: Metric, value: Double?) -> Severity {
        guard let value, let t = threshold(m) else { return .normal }
        if m.lowerIsWorse {
            return value <= t.critical ? .critical : value <= t.warning ? .warning : .normal
        }
        return value >= t.critical ? .critical : value >= t.warning ? .warning : .normal
    }

    func set(_ m: Metric, _ on: Bool) {
        if on, !enabled.contains(m) {
            // Keep the menu bar order identical to the settings order.
            enabled = Metric.allCases.filter { enabled.contains($0) || $0 == m }
        } else if !on {
            enabled.removeAll { $0 == m }
        }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            try? newValue ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        }
    }
}
