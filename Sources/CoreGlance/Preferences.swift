import Foundation
import ServiceManagement

enum Metric: String, CaseIterable, Identifiable {
    case cpu, cpuFrequency, gpu, memory, cpuTemperature, gpuTemperature, batteryTemperature, battery, power, network

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU usage"
        case .cpuFrequency: return "CPU frequency (P-cores)"
        case .gpu: return "GPU usage"
        case .memory: return "Memory used"
        case .cpuTemperature: return "CPU temperature"
        case .gpuTemperature: return "GPU temperature"
        case .batteryTemperature: return "Battery temperature"
        case .battery: return "Battery charge"
        case .power: return "System power"
        case .network: return "Network speed"
        }
    }

    /// SF Symbol shown next to the value in the menu bar.
    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .cpuFrequency: return "speedometer"
        case .gpu: return "display"
        case .memory: return "memorychip"
        case .cpuTemperature: return "thermometer.medium"
        case .gpuTemperature: return "thermometer.low"
        case .batteryTemperature: return "minus.plus.batteryblock"
        case .battery: return "battery.75percent"
        case .power: return "bolt"
        case .network: return "arrow.up.arrow.down"
        }
    }

    /// Short caption used when glyphs are off, or to tell similar glyphs apart.
    var caption: String {
        switch self {
        case .cpu: return "CPU"
        case .cpuFrequency: return "GHz"
        case .gpu: return "GPU"
        case .memory: return "RAM"
        case .cpuTemperature: return "CPU"
        case .gpuTemperature: return "GPU"
        case .batteryTemperature: return "BAT"
        case .battery: return "BAT"
        case .power: return "PWR"
        case .network: return "NET"
        }
    }
}

enum TemperatureUnit: String, CaseIterable { case celsius, fahrenheit }

/// User settings, persisted in UserDefaults.
final class Preferences: ObservableObject {
    static let shared = Preferences()
    private let defaults = UserDefaults.standard

    @Published var enabled: [Metric] { didSet { defaults.set(enabled.map(\.rawValue), forKey: "metrics") } }
    @Published var interval: Double { didSet { defaults.set(interval, forKey: "interval") } }
    @Published var showGlyphs: Bool { didSet { defaults.set(showGlyphs, forKey: "showGlyphs") } }
    @Published var captionTemperatures: Bool { didSet { defaults.set(captionTemperatures, forKey: "captionTemperatures") } }
    @Published var memoryAsPercent: Bool { didSet { defaults.set(memoryAsPercent, forKey: "memoryAsPercent") } }
    @Published var unit: TemperatureUnit { didSet { defaults.set(unit.rawValue, forKey: "unit") } }

    private init() {
        let stored = defaults.stringArray(forKey: "metrics")?.compactMap(Metric.init(rawValue:))
        enabled = stored ?? [.cpu, .gpu, .memory, .cpuTemperature, .batteryTemperature]
        interval = defaults.object(forKey: "interval") as? Double ?? 2
        showGlyphs = defaults.object(forKey: "showGlyphs") as? Bool ?? true
        captionTemperatures = defaults.object(forKey: "captionTemperatures") as? Bool ?? true
        memoryAsPercent = defaults.bool(forKey: "memoryAsPercent")
        unit = TemperatureUnit(rawValue: defaults.string(forKey: "unit") ?? "") ?? .celsius
    }

    func isEnabled(_ m: Metric) -> Bool { enabled.contains(m) }

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
