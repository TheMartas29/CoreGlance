import XCTest
@testable import CoreGlance

final class NetworkRateTests: XCTestCase {
    func testSimpleDelta() {
        // 1000 B in / 500 B out over 2 s = 500 B/s down, 250 B/s up (ručně spočteno).
        let r = NetworkReader.rate(previous: ["en0": (inBytes: 100, outBytes: 50)],
                                   current: ["en0": (inBytes: 1100, outBytes: 550)], dt: 2)
        XCTAssertEqual(r.down, 500, accuracy: 1e-9)
        XCTAssertEqual(r.up, 250, accuracy: 1e-9)
    }

    func testCounterWrapUInt32() {
        // old = max - 9, new = 10: mezi nimi 10 bajtů do wrapu + 10 po něm = 20 bajtů; dt 1 s.
        let r = NetworkReader.rate(previous: ["en0": (inBytes: UInt32.max - 9, outBytes: UInt32.max - 9)],
                                   current: ["en0": (inBytes: 10, outBytes: 10)], dt: 1)
        XCTAssertEqual(r.down, 20, accuracy: 1e-9)
        XCTAssertEqual(r.up, 20, accuracy: 1e-9)
    }

    func testInterfaceWithoutPreviousSampleIsIgnored() {
        let r = NetworkReader.rate(previous: ["en0": (inBytes: 0, outBytes: 0)],
                                   current: ["en0": (inBytes: 100, outBytes: 0),
                                             "en1": (inBytes: 999_999, outBytes: 999_999)], dt: 1)
        XCTAssertEqual(r.down, 100, accuracy: 1e-9)
        XCTAssertEqual(r.up, 0, accuracy: 1e-9)
    }

    func testSumsOverInterfaces() {
        let r = NetworkReader.rate(previous: ["en0": (inBytes: 0, outBytes: 0), "en1": (inBytes: 0, outBytes: 0)],
                                   current: ["en0": (inBytes: 100, outBytes: 10), "en1": (inBytes: 200, outBytes: 20)], dt: 1)
        XCTAssertEqual(r.down, 300, accuracy: 1e-9)
        XCTAssertEqual(r.up, 30, accuracy: 1e-9)
    }

    func testNonPositiveDtIsClampedToOneMillisecond() {
        // dt je ořezán na 0.001 s: 5 B / 0.001 s = 5000 B/s (nulový i záporný dt).
        for dt in [0.0, -3.0] {
            let r = NetworkReader.rate(previous: ["en0": (inBytes: 0, outBytes: 0)],
                                       current: ["en0": (inBytes: 5, outBytes: 5)], dt: dt)
            XCTAssertEqual(r.down, 5000, accuracy: 1e-6)
            XCTAssertEqual(r.up, 5000, accuracy: 1e-6)
        }
    }

    func testIsVirtual() {
        XCTAssertTrue(NetworkReader.isVirtual("utun0"))
        XCTAssertTrue(NetworkReader.isVirtual("awdl0"))
        XCTAssertTrue(NetworkReader.isVirtual("bridge0"))
        XCTAssertTrue(NetworkReader.isVirtual("llw0"))
        XCTAssertFalse(NetworkReader.isVirtual("en0"))
    }
}

final class MemoryStatsTests: XCTestCase {
    func testStatsFromVMStatistics() {
        var vm = vm_statistics64()
        vm.internal_page_count = 1000
        vm.purgeable_count = 100
        vm.external_page_count = 400
        vm.wire_count = 300
        vm.compressor_page_count = 200
        let page = 16384.0
        let s = MemoryReader.stats(from: vm, pageSize: page, total: 8_000_000_000)
        // Ruční výpočet: app = (1000 − 100) × 16384, cached = (400 + 100) × 16384.
        XCTAssertEqual(s.app, 900 * 16384)
        XCTAssertEqual(s.wired, 300 * 16384)
        XCTAssertEqual(s.compressed, 200 * 16384)
        XCTAssertEqual(s.cached, 500 * 16384)
        XCTAssertEqual(s.used, (900 + 300 + 200) * 16384)
        XCTAssertEqual(s.total, 8_000_000_000)
    }
}
