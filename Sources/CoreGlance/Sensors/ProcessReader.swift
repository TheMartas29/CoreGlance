import Foundation

// MARK: - Top processes
//
// Privacy: process names only ever live in `Snapshot.topProcesses` and are shown in the popover.
// They must never reach `--dump` / Save diagnostics (users attach that output to public issues).

/// One reading of a process: accumulated CPU time (user + system) in nanoseconds.
struct ProcessSample: Equatable {
    var pid: Int32
    var name: String
    var cpuNanos: UInt64
}

/// CPU use of one process; `cpu` is in percent of one core (100 = one full core, like Activity Monitor).
struct ProcessUsage: Equatable {
    var pid: Int32
    var name: String
    var cpu: Double
}

final class ProcessReader {
    typealias Source = () -> [ProcessSample]

    private let source: Source
    private let clock: () -> TimeInterval
    private let count: Int
    private var previous: [Int32: ProcessSample] = [:]
    private var previousTime: TimeInterval?

    /// `source` and `clock` are injectable so tests feed fixture processes instead of the live system.
    init(count: Int = 5,
         source: @escaping Source = ProcessReader.liveSource,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.count = count
        self.source = source
        self.clock = clock
    }

    // MARK: Pure logic

    /// CPU % per process from two readings `dt` seconds apart. Skipped: processes missing from `previous`
    /// (just started), ones whose name changed (pid reused), a counter that went down (wrap / reuse),
    /// empty names, and everything when `dt` is zero or negative.
    static func usages(previous: [Int32: ProcessSample], current: [ProcessSample], dt: TimeInterval) -> [ProcessUsage] {
        guard dt > 0 else { return [] }
        var result: [ProcessUsage] = []
        for now in current where !now.name.isEmpty {
            guard let old = previous[now.pid], old.name == now.name, now.cpuNanos >= old.cpuNanos else { continue }
            let seconds = Double(now.cpuNanos - old.cpuNanos) / 1e9
            result.append(ProcessUsage(pid: now.pid, name: now.name, cpu: seconds / dt * 100))
        }
        return result
    }

    /// The `count` busiest processes. Equal CPU % is ordered by name, then pid, so the list does not flicker.
    /// Idle processes (0 %) are left out.
    static func top(_ usages: [ProcessUsage], count: Int) -> [ProcessUsage] {
        guard count > 0 else { return [] }
        let busy = usages.filter { $0.cpu > 0 }.sorted {
            if $0.cpu != $1.cpu { return $0.cpu > $1.cpu }
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.pid < $1.pid
        }
        return Array(busy.prefix(count))
    }

    /// Popover rows: shortened name and "12.3%" text. Empty input gives no rows, so the section stays hidden.
    static func rows(_ usages: [ProcessUsage]) -> [(name: String, value: String)] {
        usages.map { u in
            let name = u.name.count > 24 ? String(u.name.prefix(23)) + "…" : u.name
            return (name, String(format: "%.1f%%", u.cpu))
        }
    }

    /// Mach absolute-time ticks to nanoseconds (`numer / denom` from `mach_timebase_info`).
    static func nanoseconds(ticks: UInt64, numer: UInt32, denom: UInt32) -> UInt64 {
        guard denom > 0 else { return ticks }
        return UInt64(min(Double(ticks) * Double(numer) / Double(denom), Double(UInt64.max / 2)))
    }

    // MARK: Sampling

    /// Top processes since the previous call; empty on the first call (it only stores the baseline).
    /// Processes that disappeared drop out of the baseline automatically.
    func sample() -> [ProcessUsage] {
        let current = source()
        let now = clock()
        defer {
            previous = Dictionary(current.map { ($0.pid, $0) }, uniquingKeysWith: { _, last in last })
            previousTime = now
        }
        guard let last = previousTime else { return [] }
        return Self.top(Self.usages(previous: previous, current: current, dt: now - last), count: count)
    }

    /// Forget the baseline (used while the feature is switched off, so re-enabling does not average over minutes).
    func reset() {
        previous = [:]
        previousTime = nil
    }

    /// All processes the current user can read through libproc. Unreadable pids and empty names are skipped.
    static func liveSource() -> [ProcessSample] {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        let needed = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard needed > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(needed) / MemoryLayout<Int32>.size + 32)
        let bytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(pids.count * MemoryLayout<Int32>.size))
        guard bytes > 0 else { return [] }
        var result: [ProcessSample] = []
        var nameBuffer = [CChar](repeating: 0, count: 64)
        for pid in pids.prefix(Int(bytes) / MemoryLayout<Int32>.size) where pid > 0 {
            var info = proc_taskinfo()
            let size = Int32(MemoryLayout<proc_taskinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }
            guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
            let name = String(cString: nameBuffer)
            guard !name.isEmpty else { continue }
            let ticks = info.pti_total_user &+ info.pti_total_system
            result.append(ProcessSample(pid: pid, name: name, cpuNanos: nanoseconds(ticks: ticks, numer: tb.numer, denom: tb.denom)))
        }
        return result
    }
}
