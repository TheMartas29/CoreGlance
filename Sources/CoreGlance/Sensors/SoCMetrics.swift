import Foundation
import IOKit

struct ClusterFrequency {
    var mhz: Double = 0       // average frequency while active
    var maxMHz: Double = 0    // highest DVFS state of the cluster
}

struct SoCStats {
    var eCluster = ClusterFrequency()
    var pCluster = ClusterFrequency()
    var gpuMHz: Double?
    var gpuMaxMHz: Double?
    var cpuWatts: Double?
    var gpuWatts: Double?
    var aneWatts: Double?
    var dramWatts: Double?
}

/// Apple Silicon frequencies and power from IOReport residencies + the pmgr DVFS tables
/// (no root required — this is how MX Power Gadget / macmon get their numbers).
final class SoCMetrics {
    private let report: IOReport
    private let eFreqs: [Double]    // MHz, ascending DVFS states
    private let pFreqs: [Double]
    private let gpuFreqs: [Double]  // MHz, without the leading "off" (0 Hz) entry

    init?() {
        guard let report = IOReport(groups: [("Energy Model", nil),
                                             ("CPU Stats", "CPU Core Performance States"),
                                             ("GPU Stats", "GPU Performance States")]) else { return nil }
        let tables = Self.readDVFSTables()
        self.report = report
        eFreqs = tables["voltage-states1-sram"] ?? []
        pFreqs = tables["voltage-states5-sram"] ?? []
        gpuFreqs = (tables["voltage-states9"] ?? []).filter { $0 > 0 }
        _ = report.sample()  // prime the delta
    }

    /// Raw DVFS value -> MHz. Values >= 100 000 000 are Hz, smaller ones kHz.
    static func megahertz(_ raw: UInt32) -> Double {
        Double(raw) >= 100_000_000 ? Double(raw) / 1_000_000 : Double(raw) / 1_000
    }

    /// The `pmgr` node stores (frequency, voltage) UInt32 pairs. M1–M3 store CPU frequency
    /// in Hz; M4 stores CPU frequency in kHz (Hz no longer fits 32 bits) — detected by magnitude.
    /// M6 keeps the tables in `pmgr-child@…` nodes instead of `pmgr` (RESEARCH.md, #2).
    private static func readDVFSTables() -> [String: [Double]] {
        var nodes: [(name: String, tables: [String: Data])] = []
        IORegistry.forEach(class: "AppleARMIODevice") { entry in
            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &name) == kIOReturnSuccess,
                  let props = IORegistry.properties(entry) else { return }
            var tables: [String: Data] = [:]
            for (key, value) in props where key.hasPrefix("voltage-states") {
                if let data = value as? Data { tables[key] = data }
            }
            nodes.append((String(cString: name), tables))
        }
        // `pmgr` first, so chips with tables on both nodes (M1–M4) keep today's values.
        let ordered = nodes.filter { $0.name == "pmgr" } + nodes.filter { $0.name != "pmgr" }
        return mergeDVFSTables(ordered)
    }

    /// Data of `voltage-states*` -> MHz of the (frequency, voltage) UInt32 pairs; incomplete trailing bytes are dropped.
    static func parseDVFS(_ data: Data) -> [Double] {
        data.withUnsafeBytes { buf in
            stride(from: 0, to: buf.count - 7, by: 8).map { megahertz(buf.loadUnaligned(fromByteOffset: $0, as: UInt32.self)) }
        }
    }

    /// Merges `voltage-states*` tables of `pmgr` and `pmgr-child*` nodes; the first node in input order wins per key.
    static func mergeDVFSTables(_ nodes: [(name: String, tables: [String: Data])]) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        for node in nodes where node.name == "pmgr" || node.name.hasPrefix("pmgr-child") {
            for (key, data) in node.tables where key.hasPrefix("voltage-states") && result[key] == nil {
                result[key] = parseDVFS(data)
            }
        }
        return result
    }

    enum Cluster { case efficiency, performance }

    /// E… -> efficiency, P… / M… -> performance (M6 "MCPU" cores run on the P-cluster table).
    static func cluster(forChannel name: String) -> Cluster? {
        switch name.first {
        case "E": return .efficiency
        case "P", "M": return .performance
        default: return nil
        }
    }

    private static let inactiveStates: Set<String> = ["IDLE", "DOWN", "OFF"]

    /// Active residency weighted against the DVFS table: (active ticks, Σ ticks×MHz).
    private func residency(_ channel: IOReport.Channel, freqs: [Double]) -> (active: Double, weighted: Double) {
        var active = 0.0, weighted = 0.0, index = 0
        for state in report.states(channel) {
            if Self.inactiveStates.contains(state.name) { continue }
            defer { index += 1 }
            guard index < freqs.count, state.residency > 0 else { continue }
            active += Double(state.residency)
            weighted += Double(state.residency) * freqs[index]
        }
        return (active, weighted)
    }

    /// Energy counter value -> joules; nil for a unit that is not an energy unit.
    static func joulesIfKnown(_ value: Int64, unit: String) -> Double? {
        switch unit.trimmingCharacters(in: .whitespaces) {
        case "mJ": return Double(value) / 1e3
        case "uJ", "µJ": return Double(value) / 1e6
        case "nJ": return Double(value) / 1e9
        default: return nil
        }
    }

    private static func joules(_ value: Int64, unit: String) -> Double {
        joulesIfKnown(value, unit: unit) ?? 0
    }

    /// True for the channel that carries CPU energy. Only `Energy Model` / `CPU Energy` (M1–M4) is known:
    /// the M6 dump lists no CPU energy channel there at all (RESEARCH.md, coreglance#66), so no names are guessed.
    static func isCPUEnergyChannel(group: String, subGroup: String?, name: String, unit: String) -> Bool {
        group == "Energy Model" && name == "CPU Energy" && joulesIfKnown(0, unit: unit) != nil
    }

    /// Σ joules of all CPU energy channels; nil when no channel matches (cpuWatts stays nil).
    static func cpuJoules(_ channels: [(group: String, subGroup: String?, name: String, unit: String, value: Int64)]) -> Double? {
        var total: Double?
        for c in channels where isCPUEnergyChannel(group: c.group, subGroup: c.subGroup, name: c.name, unit: c.unit) {
            total = (total ?? 0) + (joulesIfKnown(c.value, unit: c.unit) ?? 0)
        }
        return total
    }

    func sample() -> SoCStats? {
        guard let (channels, seconds) = report.sample(), seconds > 0 else { return nil }
        var s = SoCStats()
        var e = (active: 0.0, weighted: 0.0), p = (active: 0.0, weighted: 0.0)
        var cpuJ: Double?, gpuJ: Double?, aneJ = 0.0, dramJ = 0.0

        for c in channels {
            switch (c.group, c.subGroup) {
            case ("CPU Stats", "CPU Core Performance States"):
                // Channels are named ECPUn / PCPUn (plus PCPU1n etc. on chips with two P clusters),
                // on M6 EACC_ECPUn / PACC0_PCPUn / PACC0_MCPUn.
                switch Self.cluster(forChannel: c.name) {
                case .efficiency?:
                    let r = residency(c, freqs: eFreqs); e.active += r.active; e.weighted += r.weighted
                case .performance?:
                    let r = residency(c, freqs: pFreqs); p.active += r.active; p.weighted += r.weighted
                case nil:
                    break
                }
            case ("GPU Stats", "GPU Performance States") where c.name == "GPUPH":
                let r = residency(c, freqs: gpuFreqs)
                s.gpuMHz = r.active > 0 ? r.weighted / r.active : 0
            case ("Energy Model", _):
                let j = Self.joules(report.integer(c), unit: c.unit)
                if Self.isCPUEnergyChannel(group: c.group, subGroup: c.subGroup, name: c.name, unit: c.unit) {
                    cpuJ = (cpuJ ?? 0) + j
                } else if c.name == "GPU Energy" { gpuJ = j }
                else if c.name == "GPU", gpuJ == nil { gpuJ = j }  // older chips have no "GPU Energy"
                else if c.name.hasPrefix("ANE") { aneJ += j }
                else if c.name.hasPrefix("DRAM") { dramJ += j }
            default:
                break
            }
        }

        s.eCluster = ClusterFrequency(mhz: e.active > 0 ? e.weighted / e.active : (eFreqs.first ?? 0), maxMHz: eFreqs.last ?? 0)
        s.pCluster = ClusterFrequency(mhz: p.active > 0 ? p.weighted / p.active : (pFreqs.first ?? 0), maxMHz: pFreqs.last ?? 0)
        if gpuFreqs.isEmpty { s.gpuMHz = nil } else { s.gpuMaxMHz = gpuFreqs.max() }
        s.cpuWatts = cpuJ.map { $0 / seconds }
        s.gpuWatts = gpuJ.map { $0 / seconds }
        s.aneWatts = aneJ / seconds
        s.dramWatts = dramJ / seconds
        return s
    }
}
