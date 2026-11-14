import XCTest
@testable import CoreGlance

/// Disk activity: pure rate + Statistics parsing + Snapshot/renderer wiring. Expected values are hand-computed.
final class DiskIOTests: XCTestCase {
    // MARK: rate

    func testRateIsBytesDeltaOverSeconds() {
        // read: 5_000_000 - 3_000_000 = 2 MB in 2 s = 1 MB/s; write: 700 - 100 = 600 B in 2 s = 300 B/s
        let r = DiskIOReader.rate(previous: [1: (read: 3_000_000, write: 100)], current: [1: (read: 5_000_000, write: 700)], dt: 2)
        XCTAssertEqual(r.read, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(r.write, 300, accuracy: 0.001)
    }

    func testRateSumsControllers() {
        let r = DiskIOReader.rate(previous: [1: (read: 0, write: 0), 2: (read: 10, write: 20)],
                                  current: [1: (read: 100, write: 0), 2: (read: 60, write: 220)], dt: 1)
        XCTAssertEqual(r.read, 150, accuracy: 0.001)   // 100 + 50
        XCTAssertEqual(r.write, 200, accuracy: 0.001)  // 0 + 200
    }

    func testRateClampsTinyDtToOneMillisecond() {
        // 1000 bytes in max(0, 1 ms) = 1_000_000 B/s, not infinity
        let r = DiskIOReader.rate(previous: [1: (read: 0, write: 0)], current: [1: (read: 1000, write: 0)], dt: 0)
        XCTAssertEqual(r.read, 1_000_000, accuracy: 0.001)
        let neg = DiskIOReader.rate(previous: [1: (read: 0, write: 0)], current: [1: (read: 1000, write: 0)], dt: -5)
        XCTAssertEqual(neg.read, 1_000_000, accuracy: 0.001)
    }

    func testRateIgnoresNewDevice() {
        let r = DiskIOReader.rate(previous: [:], current: [7: (read: 9_000_000_000, write: 9_000_000_000)], dt: 1)
        XCTAssertEqual(r.read, 0)
        XCTAssertEqual(r.write, 0)
    }

    func testRateCounterDropGivesZeroNotHugeValue() {
        // device reattached: counters restarted below the previous value (no 32/64-bit wrap here)
        let r = DiskIOReader.rate(previous: [1: (read: 5_000_000, write: 8_000_000)], current: [1: (read: 1000, write: 9_000_000)], dt: 1)
        XCTAssertEqual(r.read, 0)
        XCTAssertEqual(r.write, 1_000_000, accuracy: 0.001)
    }

    func testRateHandlesCountersAbove32Bits() {
        // 5 TB read counter + 2 GiB in one second
        let base: UInt64 = 5_000_000_000_000
        let r = DiskIOReader.rate(previous: [1: (read: base, write: 0)], current: [1: (read: base + 2_147_483_648, write: 0)], dt: 1)
        XCTAssertEqual(r.read, 2_147_483_648, accuracy: 0.001)
    }

    // MARK: Statistics parsing

    func testTotalsSumsReadAndWriteBytes() {
        let stats: [[String: Any]] = [
            ["Bytes (Read)": NSNumber(value: 100), "Bytes (Write)": NSNumber(value: 10), "Operations (Read)": NSNumber(value: 5)],
            ["Bytes (Read)": NSNumber(value: UInt64(5_000_000_000_000)), "Bytes (Write)": NSNumber(value: 20)],
        ]
        let t = DiskIOReader.totals(of: stats)
        XCTAssertEqual(t.read, 5_000_000_000_100)
        XCTAssertEqual(t.write, 30)
    }

    func testTotalsSkipsMissingOrWrongTypedEntries() {
        let stats: [[String: Any]] = [
            ["Bytes (Read)": NSNumber(value: 50)],                                 // write missing → skipped
            ["Bytes (Read)": "100", "Bytes (Write)": NSNumber(value: 5)],          // string → skipped
            [:],
            ["Bytes (Read)": NSNumber(value: 7), "Bytes (Write)": NSNumber(value: 3)],
        ]
        let t = DiskIOReader.totals(of: stats)
        XCTAssertEqual(t.read, 7)
        XCTAssertEqual(t.write, 3)
        let none = DiskIOReader.totals(of: [])
        XCTAssertEqual(none.read, 0)
        XCTAssertEqual(none.write, 0)
    }

    func testTotalsIgnoresNegativeNumbers() {
        let t = DiskIOReader.totals(of: [["Bytes (Read)": NSNumber(value: -1), "Bytes (Write)": NSNumber(value: 4)]])
        XCTAssertEqual(t.read, 0)
        XCTAssertEqual(t.write, 0)
    }

    // MARK: Metric / Snapshot

    func testMetricCatalogue() {
        let m = Metric.diskActivity
        XCTAssertTrue(Metric.allCases.contains(m))
        XCTAssertEqual(m.group, .disk)
        XCTAssertFalse(m.title.isEmpty)
        XCTAssertFalse(m.symbol.isEmpty)
        XCTAssertEqual(m.caption, "IO")
    }

    func testAvailabilityFollowsControllers() {
        var s = Snapshot()
        XCTAssertTrue(Metric.diskActivity.isAvailable(in: s))   // not sampled yet
        s.sampled = true
        XCTAssertFalse(Metric.diskActivity.isAvailable(in: s))  // sampled, no controller found
        s.diskIO = DiskIOStats(read: 0, write: 0)
        XCTAssertTrue(Metric.diskActivity.isAvailable(in: s))   // controller present, idle
    }

    // MARK: renderer / preferences

    func testRendererStacksWriteOverRead() {
        var s = Snapshot()
        s.diskIO = DiskIOStats(read: 2_097_152, write: 512)  // 2 MiB/s, 512 B/s
        let t = StatusBarRenderer.stackedText(for: .diskActivity, in: s)
        XCTAssertEqual(t?.top, "W512B")
        XCTAssertEqual(t?.bottom, "R2.0M")
    }

    func testRendererWithoutDataShowsDashesAndDoesNotCrash() {
        let t = StatusBarRenderer.stackedText(for: .diskActivity, in: Snapshot())
        XCTAssertEqual(t?.top, "W–")
        XCTAssertEqual(t?.bottom, "R–")
        XCTAssertEqual(StatusBarRenderer.value(for: .diskActivity, in: Snapshot(), prefs: Preferences.shared), "")
    }

    func testOldSavedSettingsDoNotGainDiskActivity() {
        XCTAssertEqual(Preferences.initialMetrics(stored: ["cpu", "disk"]), [.cpu, .disk])
        XCTAssertFalse(Preferences.initialMetrics(stored: nil).contains(.diskActivity))
        XCTAssertEqual(Preferences.initialMetrics(stored: ["diskActivity", "cpu"]), [.cpu, .diskActivity])
    }
}
