import Foundation
import Combine

struct Snapshot {
    var cores: [(kind: CoreKind, load: Double)] = []
    var cpu: Double = 0
    var cpuP: Double?
    var cpuE: Double?
    var soc: SoCStats?
    var nominalGHz: Double?
    var gpu: Double?
    var memory = MemoryStats()
    var thermals = ThermalStats()
    var battery = BatteryStats()
    var network = NetworkStats()
    var disk = DiskStats()
    /// False until the first real reading; until then every metric counts as available.
    var sampled = false

    /// Battery temperature: the gas gauge value, falling back to the SMC battery sensors.
    var batteryTemperature: Double? { battery.temperature ?? thermals.battery }
}

extension Metric {
    /// Whether this Mac actually delivers a value for the metric (no fan on a MacBook Air,
    /// no battery on a Mac mini…). Unavailable metrics are hidden from settings and the bar.
    func isAvailable(in s: Snapshot) -> Bool {
        guard s.sampled else { return true }
        switch self {
        case .cpu, .memory, .memoryPressure, .compressed, .swap, .network: return true
        case .cpuCores: return s.cpuP != nil && s.cpuE != nil
        case .cpuFrequency: return s.soc != nil || s.nominalGHz != nil
        case .eFrequency: return s.soc != nil && s.cpuE != nil
        case .gpu: return s.gpu != nil
        case .gpuFrequency: return s.soc?.gpuMHz != nil
        case .disk: return s.disk.total > 0
        case .cpuTemperature: return s.thermals.cpu != nil
        case .gpuTemperature: return s.thermals.gpu != nil
        case .batteryTemperature: return s.batteryTemperature != nil
        case .ssdTemperature: return s.thermals.ssd != nil
        case .battery: return s.battery.present
        case .power: return s.thermals.systemWatts != nil || s.battery.systemPowerIn != nil
        case .fan: return !s.thermals.fans.isEmpty
        }
    }
}

/// Polls every sensor on a background queue and publishes snapshots on the main thread.
final class Monitor: ObservableObject {
    @Published private(set) var snapshot = Snapshot()

    private let queue = DispatchQueue(label: "CoreGlance.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?

    // Sensors are created lazily on the monitor queue; any of them may be unavailable.
    private var cpuLoad: CPULoad!
    private var soc: SoCMetrics?
    private var thermals: Thermals?
    private let network = NetworkReader()
    private let chipName = Sysctl.string("machdep.cpu.brand_string") ?? "Unknown CPU"

    var chip: String { chipName }

    init() {
        queue.async { [self] in
            cpuLoad = CPULoad()
            soc = SoCMetrics()
            thermals = Thermals()
            _ = cpuLoad.sample()
            _ = network.sample()
        }
    }

    func start(interval: TimeInterval) {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .milliseconds(500), repeating: interval, leeway: .milliseconds(100))
        t.setEventHandler { [weak self] in
            guard let self else { return }
            let s = self.read()
            DispatchQueue.main.async { self.snapshot = s }
        }
        t.resume()
        timer = t
    }

    private func read() -> Snapshot {
        var s = Snapshot()
        s.sampled = true
        let loads = cpuLoad.sample()
        s.cores = loads.enumerated().map { (cpuLoad.kinds.indices.contains($0.offset) ? cpuLoad.kinds[$0.offset] : .unknown, $0.element) }
        s.cpu = loads.isEmpty ? 0 : loads.reduce(0, +) / Double(loads.count)
        func average(_ kind: CoreKind) -> Double? {
            let l = s.cores.filter { $0.kind == kind }.map(\.load)
            return l.isEmpty ? nil : l.reduce(0, +) / Double(l.count)
        }
        s.cpuP = average(.performance)
        s.cpuE = average(.efficiency)
        s.soc = soc?.sample()
        if s.soc == nil, let hz = Sysctl.int("hw.cpufrequency"), hz > 0 { s.nominalGHz = Double(hz) / 1e9 }
        s.gpu = GPUReader.utilization()
        s.memory = MemoryReader.read()
        s.thermals = thermals?.sample() ?? ThermalStats()
        s.battery = BatteryReader.read()
        s.network = network.sample()
        s.disk = DiskReader.read()
        return s
    }

    /// Plain-text dump of everything the sensors see; `CoreGlance --dump` prints it.
    func diagnostics() -> String {
        queue.sync {
            _ = read()
            Thread.sleep(forTimeInterval: 1)
            let s = read()
            var lines = ["CoreGlance diagnostics", "chip: \(chipName)  model: \(Sysctl.string("hw.model") ?? "?")  macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)"]
            lines.append("cores: " + cpuLoad.kinds.map { $0.rawValue.isEmpty ? "?" : $0.rawValue }.joined())
            lines.append("smc sensors: \(thermals?.sensorSummary ?? "SMC unavailable")")
            lines.append("ioreport: \(soc == nil ? "unavailable" : "ok")")
            lines.append(String(describing: s.soc as Any))
            lines.append("cpu=\(s.cpu) P=\(s.cpuP as Any) E=\(s.cpuE as Any) gpu=\(s.gpu as Any)")
            lines.append(String(describing: s.memory))
            lines.append(String(describing: s.thermals))
            lines.append(String(describing: s.battery))
            lines.append(String(describing: s.network))
            return lines.joined(separator: "\n")
        }
    }
}
