import XCTest
@testable import CoreGlance

final class SensorLogicTests: XCTestCase {
    // DVFS: M1–M3 store Hz, M4 stores kHz (Hz would not fit 32 bits).
    func testMegahertzDetectsHzVersusKilohertz() {
        XCTAssertEqual(SoCMetrics.megahertz(4_400_000), 4400)          // kHz
        XCTAssertEqual(SoCMetrics.megahertz(3_204_000_000), 3204)      // Hz
        XCTAssertEqual(SoCMetrics.megahertz(600_000_000), 600)         // Hz, above the cut
        XCTAssertEqual(SoCMetrics.megahertz(0), 0)
    }

    // Tick order follows CPU_STATE_*: user, system, idle, nice.
    func testBusyFraction() {
        XCTAssertEqual(CPULoad.busyFraction(now: [100, 50, 150, 0], old: [0, 0, 0, 0]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(CPULoad.busyFraction(now: [5, 5, 5, 5], old: [5, 5, 5, 5]), 0)  // no ticks elapsed
    }

    func testBusyFractionSurvivesUInt32Wrap() {
        let old: [UInt32] = [UInt32.max - 9, 0, UInt32.max - 9, 0]
        let now: [UInt32] = [10, 0, 70, 0]  // user +20 across the wrap, idle +80
        XCTAssertEqual(CPULoad.busyFraction(now: now, old: old), 0.2, accuracy: 1e-9)
    }

    func testSMCDecodesFloatAndSp78() {
        XCTAssertEqual(SMC.decode(type: "flt ", bytes: [0x00, 0x00, 0x60, 0x40]), 3.5)  // 0x40600000 little-endian
        XCTAssertEqual(SMC.decode(type: "sp78", bytes: [0x1A, 0x80]), 26.5)
        XCTAssertEqual(SMC.decode(type: "sp78", bytes: [0xFF, 0x00]), -1)
        XCTAssertEqual(SMC.decode(type: "ui16", bytes: [0x01, 0x00]), 256)
        XCTAssertEqual(SMC.decode(type: "fpe2", bytes: [0x0F, 0xA0]), 1000)
        XCTAssertNil(SMC.decode(type: "flt ", bytes: [0, 0]))   // too short
        XCTAssertNil(SMC.decode(type: "zzzz", bytes: [1, 2, 3, 4]))
    }
}
