import Foundation

/// One reading of a metric at a point in time (seconds, any monotonic origin).
struct HistorySample: Equatable {
    var time: TimeInterval
    var value: Double
}

/// In-memory ring of recent readings for one metric. Nothing is written to disk.
struct History: Equatable {
    /// Samples older than this many seconds (relative to the newest append) are dropped.
    static let window: TimeInterval = 300
    /// Hard upper bound on the sample count, even when the interval is shorter than 1 s.
    static let capacity = 600

    private(set) var samples: [HistorySample] = []

    /// A missing reading (`nil`, sensor absent) or a non-finite one is skipped, not stored.
    mutating func append(_ value: Double?, at time: TimeInterval) {
        guard let value, value.isFinite else { return }
        samples.append(HistorySample(time: time, value: value))
        let cutoff = time - History.window
        if let firstKept = samples.firstIndex(where: { $0.time >= cutoff }), firstKept > 0 {
            samples.removeFirst(firstKept)
        }
        if samples.count > History.capacity { samples.removeFirst(samples.count - History.capacity) }
    }

    var values: [Double] { samples.map(\.value) }
}

/// Histories of the metrics the popover draws.
struct Histories: Equatable {
    var cpu = History()
    var gpu = History()
    var memory = History()
    var cpuTemperature = History()
    /// Throughput in bytes per second.
    var networkDown = History()
    var networkUp = History()
    var diskRead = History()
    var diskWrite = History()

    /// Adds the readings of one snapshot. Usage values are fractions 0...1, temperature is °C, rates are bytes/s.
    mutating func record(_ s: Snapshot, at time: TimeInterval) {
        cpu.append(s.cpu, at: time)
        gpu.append(s.gpu, at: time)
        memory.append(s.memory.total > 0 ? s.memory.used / s.memory.total : nil, at: time)
        cpuTemperature.append(s.thermals.cpu?.average, at: time)
        networkDown.append(s.network.down, at: time)
        networkUp.append(s.network.up, at: time)
        diskRead.append(s.diskIO?.read, at: time)
        diskWrite.append(s.diskIO?.write, at: time)
    }
}

/// Pure conversion of a history into chart geometry, independent of SwiftUI.
enum Sparkline {
    /// Usage metrics (CPU, GPU, memory) always use the full 0...100 % scale.
    static let percentRange: ClosedRange<Double> = 0...1
    /// Smallest temperature span, so sensor noise of 0.5 °C does not look like a jump.
    static let minimumTemperatureSpan = 10.0

    /// Smallest throughput scale (100 kB/s), so background chatter does not look like a spike.
    static let minimumRateSpan = 100_000.0

    /// Throughput scale: always from 0, up to the highest value of both series (so a pair such as
    /// download/upload is drawn on one scale), never narrower than `minimumRateSpan`.
    static func rateRange(_ values: [Double], _ other: [Double] = []) -> ClosedRange<Double> {
        let peak = (values + other).filter { $0.isFinite }.max() ?? 0
        return 0...max(peak, minimumRateSpan)
    }

    /// Throughput graphs need `showHistory` on and, for disk, an available reading.
    static func showsRateGraph(showHistory: Bool, available: Bool) -> Bool { showHistory && available }

    /// Scale fitted to the data, never narrower than `minSpan`; the data stay centred.
    static func autoRange(_ values: [Double], minSpan: Double = minimumTemperatureSpan) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...minSpan }
        let span = max(hi - lo, minSpan)
        let mid = (lo + hi) / 2
        return (mid - span / 2)...(mid + span / 2)
    }

    /// Points in the unit square: x = 0 is `window` seconds before `now`, x = 1 is `now`;
    /// y = 0 is the bottom of `range`, y = 1 the top (values outside are clamped).
    /// An empty series gives no points, a single sample gives one point.
    static func points(_ samples: [HistorySample], now: TimeInterval, window: TimeInterval = History.window,
                       range: ClosedRange<Double>) -> [(x: Double, y: Double)] {
        let span = range.upperBound - range.lowerBound
        return samples.map { s in
            let x = min(max(1 - (now - s.time) / window, 0), 1)
            let y = span > 0 ? min(max((s.value - range.lowerBound) / span, 0), 1) : 0.5
            return (x, y)
        }
    }
}
