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
        let keys = smc.allKeys()
        // Only keep sensors that currently report a plausible temperature.
        func sensors(_ match: (String) -> Bool) -> [String] {
            keys.filter(match).filter { key in smc.value(key).map { $0 > 0 && $0 < 150 } ?? false }
        }
        #if arch(arm64)
        cpuKeys = sensors { $0.hasPrefix("Tp") || $0.hasPrefix("Te") }
        gpuKeys = sensors { $0.hasPrefix("Tg") }
        #else
        let intelCPU: Set<String> = ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TCXC"]
        cpuKeys = sensors { intelCPU.contains($0) || ($0.hasPrefix("TC") && $0.hasSuffix("C") && $0.count == 4) }
        gpuKeys = sensors { ["TG0P", "TG0D", "TG0H", "TGDD"].contains($0) }
        #endif
        batteryKeys = sensors { $0.count == 4 && $0.hasPrefix("TB") && $0.hasSuffix("T") }
        ssdKeys = sensors { $0 == "TH0x" || $0 == "TH0a" || $0 == "TH0b" || $0 == "TH0A" }
        fanCount = Int(smc.value("FNum") ?? 0)
    }

    private func reading(_ keys: [String], valid: ClosedRange<Double> = 1...150) -> Reading? {
        let values = keys.compactMap { smc.value($0) }.filter { valid.contains($0) }
        guard !values.isEmpty else { return nil }
        return Reading(average: values.reduce(0, +) / Double(values.count), max: values.max()!)
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
