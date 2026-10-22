import Foundation
import IOKit
import IOKit.ps

enum Sysctl {
    static func int(_ name: String) -> Int? {
        var value: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        // Some sysctls are 32-bit; the unused upper bytes stay zero on little-endian.
        return Int(value)
    }

    static func string(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}

enum IORegistry {
    static func properties(_ entry: io_registry_entry_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess else { return nil }
        return props?.takeRetainedValue() as? [String: Any]
    }

    static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    static func data(_ entry: io_registry_entry_t, _ key: String) -> [UInt8]? {
        (property(entry, key) as? Data).map { [UInt8]($0) }
    }

    static func int(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        let value = property(entry, key)
        if let n = value as? NSNumber { return n.intValue }
        if let d = value as? Data, d.count >= 4 { return Int(d.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }) }
        return nil
    }

    /// Calls `body` for every service of the given class.
    static func forEach(class name: String, _ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            body(entry)
            IOObjectRelease(entry)
        }
    }
}

// MARK: - Memory

struct MemoryStats {
    var total: Double = 0, used: Double = 0, app: Double = 0, wired: Double = 0, compressed: Double = 0, cached: Double = 0
    var swapUsed: Double = 0, swapTotal: Double = 0
    var pressure: Int = 1  // 1 normal, 2 warning, 4 critical
}

enum MemoryReader {
    static func read() -> MemoryStats {
        var s = MemoryStats()
        s.total = Double(ProcessInfo.processInfo.physicalMemory)
        var vm = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &vm) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        if kr == KERN_SUCCESS {
            let page = Double(vm_kernel_page_size)
            // Same formula as Activity Monitor's "Memory Used" = App + Wired + Compressed.
            s.app = Double(vm.internal_page_count - vm.purgeable_count) * page
            s.wired = Double(vm.wire_count) * page
            s.compressed = Double(vm.compressor_page_count) * page
            s.cached = Double(vm.external_page_count + vm.purgeable_count) * page
            s.used = s.app + s.wired + s.compressed
        }
        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            s.swapUsed = Double(swap.xsu_used)
            s.swapTotal = Double(swap.xsu_total)
        }
        s.pressure = Sysctl.int("kern.memorystatus_vm_pressure_level") ?? 1
        return s
    }
}

// MARK: - GPU utilization

enum GPUReader {
    /// "Device Utilization %" from IOAccelerator (the value Activity Monitor's GPU history uses).
    /// Works on Apple Silicon and Intel/AMD; with several GPUs the busiest one is reported.
    static func utilization() -> Double? {
        var best: Double?
        IORegistry.forEach(class: "IOAccelerator") { entry in
            guard let stats = IORegistry.property(entry, "PerformanceStatistics") as? [String: Any],
                  let value = (stats["Device Utilization %"] ?? stats["GPU Activity(%)"]) as? NSNumber else { return }
            best = max(best ?? 0, value.doubleValue / 100)
        }
        return best
    }
}

// MARK: - Battery

struct BatteryStats {
    var present = false
    var percent: Double = 0
    var charging = false, pluggedIn = false, fullyCharged = false
    var minutesRemaining: Int?
    var temperature: Double?      // °C
    var cycleCount: Int?
    var health: Double?           // 0...1, current max capacity vs design
    var voltage: Double?          // V
    var amperage: Double?         // A, negative = discharging
    var power: Double? { voltage.flatMap { v in amperage.map { v * $0 } } }  // W
    var systemPowerIn: Double?    // W drawn from the adapter
    var adapterWatts: Int?
}

enum BatteryReader {
    static func read() -> BatteryStats {
        var b = BatteryStats()
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return b }
        defer { IOObjectRelease(service) }
        guard let p = IORegistry.properties(service), (p["BatteryInstalled"] as? Bool) ?? true else { return b }

        func int(_ k: String) -> Int? { (p[k] as? NSNumber).map { Int(truncatingIfNeeded: $0.int64Value) } }
        b.present = true
        let current = Double(int("CurrentCapacity") ?? 0)
        let max = Double(int("MaxCapacity") ?? 100)
        // Apple Silicon reports percent directly (MaxCapacity == 100); Intel reports mAh.
        b.percent = max <= 100 ? current / 100 : (max > 0 ? current / max : 0)
        b.charging = (p["IsCharging"] as? Bool) ?? false
        b.pluggedIn = (p["ExternalConnected"] as? Bool) ?? false
        b.fullyCharged = (p["FullyCharged"] as? Bool) ?? false
        // 65535 means "still calculating"; on AC without charging there is nothing to estimate.
        if b.charging || !b.pluggedIn, let t = int(b.charging ? "AvgTimeToFull" : "AvgTimeToEmpty"), t > 0, t < 65535 { b.minutesRemaining = t }
        // Battery pack temperature in hundredths of a degree Celsius.
        if let t = int("Temperature"), t > 0 { b.temperature = Double(t) / 100 }
        b.cycleCount = int("CycleCount")
        let full = int("AppleRawMaxCapacity") ?? (max > 100 ? Int(max) : nil)
        if let full, let design = int("DesignCapacity"), design > 0 { b.health = Double(full) / Double(design) }
        if let v = int("Voltage") { b.voltage = Double(v) / 1000 }
        if let a = int("Amperage") { b.amperage = Double(a) / 1000 }
        if let telemetry = p["PowerTelemetryData"] as? [String: Any], let w = telemetry["SystemPowerIn"] as? NSNumber, w.doubleValue > 0 {
            b.systemPowerIn = w.doubleValue / 1000
        }
        if let adapter = p["AdapterDetails"] as? [String: Any], let w = adapter["Watts"] as? NSNumber { b.adapterWatts = w.intValue }
        return b
    }
}

// MARK: - Network

struct NetworkStats { var down: Double = 0; var up: Double = 0 }  // bytes per second

final class NetworkReader {
    private var previous: [String: (inBytes: UInt32, outBytes: UInt32)] = [:]
    private var previousTime: Date?

    func sample() -> NetworkStats {
        var current: [String: (inBytes: UInt32, outBytes: UInt32)] = [:]
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return NetworkStats() }
        defer { freeifaddrs(addrs) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard ifa.ifa_addr?.pointee.sa_family == UInt8(AF_LINK), let data = ifa.ifa_data,
                  ifa.ifa_flags & UInt32(IFF_UP) != 0, ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            // Skip virtual interfaces that would double count traffic.
            if ["utun", "awdl", "llw", "bridge", "gif", "stf", "anpi", "ap"].contains(where: name.hasPrefix) { continue }
            let d = data.assumingMemoryBound(to: if_data.self).pointee
            current[name] = (d.ifi_ibytes, d.ifi_obytes)
        }
        let now = Date()
        defer { previous = current; previousTime = now }
        guard let last = previousTime else { return NetworkStats() }
        let dt = max(now.timeIntervalSince(last), 0.001)
        var stats = NetworkStats()
        for (name, value) in current {
            guard let old = previous[name] else { continue }
            // Counters are 32-bit; wrapping subtraction handles the overflow.
            stats.down += Double(value.inBytes &- old.inBytes) / dt
            stats.up += Double(value.outBytes &- old.outBytes) / dt
        }
        return stats
    }
}

// MARK: - Disk

struct DiskStats { var free: Double = 0; var total: Double = 0 }

enum DiskReader {
    /// Free space on the boot volume as Finder reports it (includes purgeable space).
    static func read() -> DiskStats {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: keys) else { return DiskStats() }
        return DiskStats(free: Double(v.volumeAvailableCapacityForImportantUsage ?? 0), total: Double(v.volumeTotalCapacity ?? 0))
    }
}
