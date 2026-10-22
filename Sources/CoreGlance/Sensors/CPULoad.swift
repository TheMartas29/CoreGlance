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
        var kinds = [CoreKind](repeating: .unknown, count: count)
        var iterator: io_iterator_t = 0
        let root = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if root != 0, IORegistryEntryGetChildIterator(root, kIODeviceTreePlane, &iterator) == kIOReturnSuccess {
            var found = false
            while case let entry = IOIteratorNext(iterator), entry != 0 {
                defer { IOObjectRelease(entry) }
                guard let type = IORegistry.data(entry, "cluster-type").flatMap({ String(bytes: $0.prefix { $0 != 0 }, encoding: .ascii) }),
                      let id = IORegistry.int(entry, "logical-cpu-id"), id < count else { continue }
                kinds[id] = type == "P" ? .performance : (type == "E" ? .efficiency : .unknown)
                found = true
            }
            IOObjectRelease(iterator)
            IOObjectRelease(root)
            if found { return kinds }
        }
        if let p = Sysctl.int("hw.perflevel0.logicalcpu"), let e = Sysctl.int("hw.perflevel1.logicalcpu"), p + e == count {
            return Array(repeating: .efficiency, count: e) + Array(repeating: .performance, count: p)
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
            // Tick counters are 32-bit and wrap; &- keeps the delta correct.
            let d = (0..<stride).map { Double(now[$0] &- old[$0]) }
            let busy = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)]
            let total = busy + d[Int(CPU_STATE_IDLE)]
            return total > 0 ? busy / total : 0
        }
    }
}
