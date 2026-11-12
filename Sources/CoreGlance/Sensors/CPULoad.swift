import Foundation
import IOKit

enum CoreKind: String { case performance = "P", efficiency = "E", unknown = "" }

/// Per-core CPU load from Mach `host_processor_info`, tagged with core kind (P/E).
final class CPULoad {
    let kinds: [CoreKind]
    private var previous: [[UInt32]] = []

    init() {
        let count = Sysctl.int("hw.logicalcpu") ?? ProcessInfo.processInfo.processorCount
        kinds = Self.detectKinds(count: count)
    }

    /// Apple Silicon: each `cpuN` node in the device tree carries `cluster-type` ("E"/"P")
    /// and `logical-cpu-id`, which is the index used by host_processor_info.
    /// Falls back to hw.perflevel counts (E cores enumerate first), Intel -> all unknown.
    private static func detectKinds(count: Int) -> [CoreKind] {
        var entries: [(clusterType: String, logicalID: Int)] = []
        var iterator: io_iterator_t = 0
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if root != 0, IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == kIOReturnSuccess {
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard let type = IORegistry.data(entry, "cluster-type").flatMap({ String(bytes: $0.prefix { $0 != 0 }, encoding: .ascii) }),
                      let id = IORegistry.int(entry, "logical-cpu-id") else { continue }
                entries.append((clusterType: type, logicalID: id))
            }
            IOObjectRelease(iterator)
            IOObjectRelease(root)
        }
        var perflevel: (p: Int, e: Int)?
        if let p = Sysctl.int("hw.perflevel0.logicalcpu"), let e = Sysctl.int("hw.perflevel1.logicalcpu") {
            perflevel = (p: p, e: e)
        }
        return kinds(entries: entries, count: count, perflevel: perflevel)
    }

    /// Pure core-kind resolution. `entries` come from the device tree (`cluster-type`, `logical-cpu-id`).
    /// "P" and "M" (middle tier, shares the P cluster DVFS table, see RESEARCH.md) -> performance, "E" -> efficiency,
    /// anything else -> unknown. Entries with logicalID outside 0..<count are ignored. When no entry
    /// is usable, `perflevel` (E cores enumerate first) is used if it adds up to `count`; otherwise all unknown (Intel).
    static func kinds(entries: [(clusterType: String, logicalID: Int)], count: Int,
                      perflevel: (p: Int, e: Int)?) -> [CoreKind] {
        var kinds = [CoreKind](repeating: .unknown, count: max(count, 0))
        var found = false
        for entry in entries where entry.logicalID >= 0 && entry.logicalID < kinds.count {
            switch entry.clusterType {
            case "P", "M": kinds[entry.logicalID] = .performance
            case "E": kinds[entry.logicalID] = .efficiency
            default: kinds[entry.logicalID] = .unknown
            }
            found = true
        }
        if found { return kinds }
        if let perflevel, perflevel.p >= 0, perflevel.e >= 0, perflevel.p + perflevel.e == count {
            return Array(repeating: .efficiency, count: perflevel.e) + Array(repeating: .performance, count: perflevel.p)
        }
        return kinds
    }

    /// Returns per-core busy fraction (0...1) since the previous call.
    func sample() -> [Double] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info else { return [] }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }

        let stride = Int(CPU_STATE_MAX)
        let current: [[UInt32]] = (0..<Int(cpuCount)).map { cpu in
            (0..<stride).map { UInt32(bitPattern: info[cpu * stride + $0]) }
        }
        defer { previous = current }
        guard previous.count == current.count else { return Array(repeating: 0, count: current.count) }

        return zip(current, previous).map { now, old in
            Self.busyFraction(now: now, old: old)
        }
    }

    /// Busy fraction from two tick snapshots indexed by CPU_STATE_*.
    /// Tick counters are 32-bit and wrap; &- keeps the delta correct.
    /// Malformed input (fewer than CPU_STATE_MAX ticks, or differing lengths) yields 0 instead of trapping.
    static func busyFraction(now: [UInt32], old: [UInt32]) -> Double {
        guard now.count >= Int(CPU_STATE_MAX), now.count == old.count else { return 0 }
        let d = (0..<now.count).map { Double(now[$0] &- old[$0]) }
        let busy = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
        let total = busy + d[Int(CPU_STATE_IDLE)]
        return total > 0 ? busy / total : 0
    }
}
