import XCTest
@testable import CoreGlance

/// Bytes recorded on an Apple M6 (RESEARCH.md, issue #2, evidence 1).
final class DVFSTests: XCTestCase {
    private let states1 = Data([0xe0, 0xd4, 0x0e, 0x00, 0xee, 0x02, 0x00, 0x00])  // 0x000ED4E0 = 972 000 kHz
    private let states5 = Data([0x00, 0xf9, 0x15, 0x00, 0xee, 0x02, 0x00, 0x00])  // 0x0015F900 = 1 440 000 kHz
    private let states9 = Data([0x00, 0x00, 0x00, 0x00, 0x7d, 0x00, 0x00, 0x00,
                                0x80, 0xe9, 0xeb, 0x1d, 0xa8, 0x02, 0x00, 0x00])  // 0 Hz, 0x1DEBE980 = 502 000 000 Hz

    func testParsesRecordedM6Tables() {
        XCTAssertEqual(SoCMetrics.parseDVFS(states1).first, 972.0)
        XCTAssertEqual(SoCMetrics.parseDVFS(states5).first, 1440.0)
        XCTAssertEqual(SoCMetrics.parseDVFS(states9), [0, 502.0])
    }

    func testParseKeepsOnlyCompletePairs() {
        XCTAssertEqual(SoCMetrics.parseDVFS(Data()), [])
        XCTAssertEqual(SoCMetrics.parseDVFS(Data([1, 2, 3])), [])
        XCTAssertEqual(SoCMetrics.parseDVFS(states1 + Data([0xe0, 0xd4, 0x0e])), [972.0])  // 11 bytes
    }

    func testMergeFirstNodeWinsAndOtherNamesAreIgnored() {
        let merged = SoCMetrics.mergeDVFSTables([
            (name: "pmgr", tables: ["voltage-states1-sram": states1]),
            (name: "pmgr-child@700000", tables: ["voltage-states1-sram": states5, "voltage-states9": states9]),
            (name: "other", tables: ["voltage-states5-sram": states5]),
            (name: "pmgr-child", tables: ["voltage-states5": states5, "unrelated": states1]),
        ])
        XCTAssertEqual(merged["voltage-states1-sram"], [972.0])      // pmgr wins over the child
        XCTAssertEqual(merged["voltage-states9"], [0, 502.0])        // only in pmgr-child
        XCTAssertEqual(merged["voltage-states5"], [1440.0])
        XCTAssertNil(merged["voltage-states5-sram"])                 // node "other" ignored
        XCTAssertNil(merged["unrelated"])                            // not a voltage-states key
    }

    func testClusterFromChannelName() {
        XCTAssertEqual(SoCMetrics.cluster(forChannel: "EACC_ECPU0"), .efficiency)
        XCTAssertEqual(SoCMetrics.cluster(forChannel: "PACC0_PCPU1"), .performance)
        XCTAssertEqual(SoCMetrics.cluster(forChannel: "PACC0_MCPU2"), .performance)
        XCTAssertNil(SoCMetrics.cluster(forChannel: "GPUPH"))
        XCTAssertNil(SoCMetrics.cluster(forChannel: ""))
    }
}
