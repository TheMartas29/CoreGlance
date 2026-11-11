import Foundation

struct Reading { var average: Double; var max: Double }

struct Fan { var rpm: Double; var maxRPM: Double? }

struct ThermalStats {
    var cpu: Reading?
    var gpu: Reading?
    var battery: Double?    // hottest battery cell sensor (SMC), °C
    var ssd: Double?
    var fans: [Fan] = []
    var systemWatts: Double?  // whole-machine power from SMC (PSTR)
}

/// Temperatures, fans and system power from the SMC. Sensor keys differ per chip
/// generation, so instead of hard-coding lists the SMC is enumerated once at startup
/// and keys are classified by prefix (the approach macmon uses for M1–M4).
final class Thermals {
    private let smc: SMC
    private let cpuKeys: [String], gpuKeys: [String], batteryKeys: [String], ssdKeys: [String]
    private let fanCount: Int

    init?() {
        guard let smc = SMC() else { return nil }
        self.smc = smc
        #if arch(arm64)
        let isARM = true
        #else
        let isARM = false
        #endif
        let candidates = Thermals.classify(keys: smc.allKeys(), isARM: isARM)
        // Only keep sensors that currently report a plausible temperature.
        func plausible(_ keys: [String]) -> [String] {
            keys.filter { key in smc.value(key).map { $0 > 0 && $0 < 150 } ?? false }
        }
        cpuKeys = plausible(candidates.cpu)
        gpuKeys = plausible(candidates.gpu)
        batteryKeys = plausible(candidates.battery)
        ssdKeys = plausible(candidates.ssd)
        fanCount = Int(smc.value("FNum") ?? 0)
    }

    struct Classification: Equatable {
        var cpu: [String] = [], gpu: [String] = [], battery: [String] = [], ssd: [String] = []
    }

    /// Pure prefix classification of SMC keys into candidate sensors (no hardware access).
    static func classify(keys: [String], isARM: Bool) -> Classification {
        let intelCPU: Set<String> = ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TCXC"]
        let intelGPU: Set<String> = ["TG0P", "TG0D", "TG0H", "TGDD"]
        let ssd: Set<String> = ["TH0x", "TH0a", "TH0b", "TH0A"]
        var c = Classification()
        for k in keys {
            if isARM {
                if k.hasPrefix("Tp") || k.hasPrefix("Te") { c.cpu.append(k) }
                else if k.hasPrefix("Tg") { c.gpu.append(k) }
            } else {
                if intelCPU.contains(k) || (k.hasPrefix("TC") && k.hasSuffix("C") && k.count == 4) { c.cpu.append(k) }
                else if intelGPU.contains(k) { c.gpu.append(k) }
            }
            if k.count == 4 && k.hasPrefix("TB") && k.hasSuffix("T") { c.battery.append(k) }
            if ssd.contains(k) { c.ssd.append(k) }
        }
        return c
    }

    /// Mean and max of the values inside `valid`; nil when none qualify.
    static func aggregate(_ values: [Double], valid: ClosedRange<Double>) -> Reading? {
        let ok = values.filter { valid.contains($0) }
        guard let top = ok.max() else { return nil }
        return Reading(average: ok.reduce(0, +) / Double(ok.count), max: top)
    }

    private func reading(_ keys: [String], valid: ClosedRange<Double> = 1...150) -> Reading? {
        Thermals.aggregate(keys.compactMap { smc.value($0) }, valid: valid)
    }

    func sample() -> ThermalStats {
        var t = ThermalStats()
        // Some die sensors report garbage outside a plausible range (seen on M2), as Stats notes.
        t.cpu = reading(cpuKeys, valid: 10...120)
        t.gpu = reading(gpuKeys)
        t.battery = reading(batteryKeys)?.max
        t.ssd = reading(ssdKeys)?.max
        t.fans = (0..<fanCount).compactMap { i in
            smc.value("F\(i)Ac").map { Fan(rpm: $0, maxRPM: smc.value("F\(i)Mx")) }
        }
        if let w = smc.value("PSTR"), w > 0 { t.systemWatts = w }
        return t
    }

    var sensorSummary: String {
        "cpu=\(cpuKeys.joined(separator: ",")) gpu=\(gpuKeys.joined(separator: ",")) battery=\(batteryKeys.joined(separator: ",")) ssd=\(ssdKeys.joined(separator: ",")) fans=\(fanCount)"
    }
}
