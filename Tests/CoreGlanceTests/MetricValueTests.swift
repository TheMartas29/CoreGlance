import XCTest
@testable import CoreGlance

/// Fail-soft rule (KNOWHOW): a missing sensor shows "–", never a crash.
/// Expected strings are hand-computed from the fixture numbers in each test, not taken from the code.
/// `Preferences.shared` is read-only here except `memoryAsPercent`, which is restored in tearDown
/// (injectable defaults: coreglance#11).
final class MetricValueTests: XCTestCase {
    private let prefs = Preferences.shared
    private var savedMemoryAsPercent = false

    override func setUp() {
        super.setUp()
        savedMemoryAsPercent = prefs.memoryAsPercent
        prefs.memoryAsPercent = false
    }

    override func tearDown() {
        prefs.memoryAsPercent = savedMemoryAsPercent
        super.tearDown()
    }

    private func value(_ m: Metric, _ s: Snapshot) -> String {
        StatusBarRenderer.value(for: m, in: s, prefs: prefs)
    }

    // MARK: empty snapshot

    func testEmptySnapshotEveryMetricReturnsText() {
        let s = Snapshot()
        for m in Metric.allCases { XCTAssertNotNil(value(m, s) as String?, "\(m)") }  // must not crash
    }

    func testEmptySnapshotMissingSensorsShowDash() {
        let s = Snapshot()
        let dashes: [Metric] = [.cpuFrequency, .eFrequency, .gpu, .gpuFrequency, .disk,
                                .cpuTemperature, .gpuTemperature, .batteryTemperature, .ssdTemperature,
                                .battery, .power, .fan, .thermalState]
        for m in dashes {
            XCTAssertEqual(value(m, s), "–", "\(m)")
        }
    }

    func testEmptySnapshotZeroValuedMetrics() {
        let s = Snapshot()
        XCTAssertEqual(value(.cpu, s), "0%")
        XCTAssertEqual(value(.memory, s), "0.0GB")
        XCTAssertEqual(value(.compressed, s), "0.0GB")
        XCTAssertEqual(value(.swap, s), "0.0GB")
        XCTAssertEqual(value(.memoryPressure, s), "OK")  // MemoryStats.pressure defaults to 1
        XCTAssertEqual(value(.cpuCores, s), "")
        XCTAssertEqual(value(.network, s), "")
    }

    func testEmptySnapshotMemoryAsPercentDoesNotDivideByZero() {
        prefs.memoryAsPercent = true
        XCTAssertEqual(value(.memory, Snapshot()), "0%")  // total 0 → guarded by max(total, 1)
    }

    func testDiskWithZeroTotalIsDashEvenWithFreeSpace() {
        var s = Snapshot()
        s.disk = DiskStats(free: 50e9, total: 0)
        XCTAssertEqual(value(.disk, s), "–")
    }

    // MARK: isAvailable

    func testIsAvailableBeforeFirstSampleIsTrueForAll() {
        var s = Snapshot()
        s.sampled = false
        for m in Metric.allCases { XCTAssertTrue(m.isAvailable(in: s), "\(m)") }
    }

    func testIsAvailableAfterSampleWithEmptySnapshot() {
        var s = Snapshot()
        s.sampled = true
        // Derived from Metric.isAvailable: always-on metrics vs. metrics that need a sensor.
        let table: [(Metric, Bool)] = [
            (.cpu, true), (.memory, true), (.memoryPressure, true), (.compressed, true), (.swap, true),
            (.network, true), (.thermalState, true),
            (.cpuCores, false), (.cpuFrequency, false), (.eFrequency, false), (.gpu, false),
            (.gpuFrequency, false), (.disk, false), (.cpuTemperature, false), (.gpuTemperature, false),
            (.batteryTemperature, false), (.ssdTemperature, false), (.battery, false), (.power, false),
            (.fan, false),
        ]
        XCTAssertEqual(table.count, Metric.allCases.count, "table must cover every metric")
        for (m, expected) in table {
            XCTAssertEqual(m.isAvailable(in: s), expected, "\(m)")
        }
    }

    func testIsAvailableWithSensorsPresent() {
        var s = Snapshot()
        s.sampled = true
        s.battery.present = true
        s.thermals.fans = [Fan(rpm: 1200, maxRPM: 5000)]
        s.disk = DiskStats(free: 1, total: 2)
        XCTAssertTrue(Metric.battery.isAvailable(in: s))
        XCTAssertTrue(Metric.fan.isAvailable(in: s))
        XCTAssertTrue(Metric.disk.isAvailable(in: s))
    }

    // MARK: filled fixture

    func testMemoryInGigabytesAndPercent() {
        var s = Snapshot()
        s.memory.total = 16 * 1_073_741_824  // 16 GiB
        s.memory.used = 8 * 1_073_741_824    // 8 GiB → 8.0GB, 50 %
        s.memory.compressed = 1_610_612_736  // 1.5 GiB
        s.memory.swapUsed = 536_870_912      // 0.5 GiB
        XCTAssertEqual(value(.memory, s), "8.0GB")
        XCTAssertEqual(value(.compressed, s), "1.5GB")
        XCTAssertEqual(value(.swap, s), "0.5GB")
        prefs.memoryAsPercent = true
        XCTAssertEqual(value(.memory, s), "50%")
    }

    func testMemoryPressureLevels() {
        var s = Snapshot()
        for (pressure, text) in [(1, "OK"), (2, "Warn"), (4, "Critical")] {
            s.memory.pressure = pressure
            XCTAssertEqual(value(.memoryPressure, s), text, "pressure \(pressure)")
        }
    }

    func testDiskFreeInDecimalGigabytes() {
        var s = Snapshot()
        s.disk = DiskStats(free: 123.4e9, total: 500e9)
        XCTAssertEqual(value(.disk, s), "123GB")  // %.0f of 123.4
    }

    func testCPUFrequencyFromNominalAndFromSoC() {
        var s = Snapshot()
        s.nominalGHz = 3.2
        XCTAssertEqual(value(.cpuFrequency, s), "3.20GHz")
        s.soc = SoCStats()
        s.soc?.pCluster.mhz = 3504
        XCTAssertEqual(value(.cpuFrequency, s), "3.50GHz")  // SoC reading wins over nominal
    }

    func testSoCFrequenciesAndGPU() {
        var s = Snapshot()
        s.soc = SoCStats()
        s.soc?.eCluster.mhz = 2064
        s.soc?.gpuMHz = 1398.6
        s.gpu = 0.37
        XCTAssertEqual(value(.eFrequency, s), "2.06GHz")
        XCTAssertEqual(value(.gpuFrequency, s), "1399MHz")
        XCTAssertEqual(value(.gpu, s), "37%")
    }

    func testBatteryPowerAndFan() {
        var s = Snapshot()
        s.battery.present = true
        s.battery.percent = 0.82
        s.battery.systemPowerIn = 12.34
        s.thermals.fans = [Fan(rpm: 1200, maxRPM: nil), Fan(rpm: 2350, maxRPM: nil)]
        XCTAssertEqual(value(.battery, s), "82%")
        XCTAssertEqual(value(.power, s), "12.3W")
        XCTAssertEqual(value(.fan, s), "2350")  // fastest fan
        s.thermals.systemWatts = 20.04
        XCTAssertEqual(value(.power, s), "20.0W")  // SMC system power wins over adapter power
    }
}
