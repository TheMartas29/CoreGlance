import XCTest
@testable import CoreGlance

final class CPUEnergyTests: XCTestCase {
    // Fixture: every `Energy Model` channel of the Apple M6 / macOS 27.2 `--dump` (coreglance#66) …
    private let m6EnergyModel: [(name: String, unit: String)] = [
        ("GPU Energy", "nJ"), ("PCIe Port 0 Energy", "uJ"), ("PCIe Port 2 Energy", "uJ"),
        ("apciec3 Energy", "uJ"), ("apciec1 Energy", "uJ"), ("apciec0 Energy", "uJ"),
    ]
    // … and the CPU channels of the same dump that are residencies (unit 24Mticks), not energy.
    private let m6CPUStats: [(sub: String, name: String)] = [
        ("CPU Complex Performance States", "EACC"), ("CPU Complex Performance States", "PACC0"),
        ("CPU Core Performance States", "EACC_ECPU0"), ("CPU Core Performance States", "PACC0_MCPU2"),
    ]

    func testAcceptsCPUEnergyOfM1ToM4() {
        XCTAssertTrue(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: "", name: "CPU Energy", unit: "mJ"))
        XCTAssertTrue(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: nil, name: "CPU Energy", unit: "nJ"))
    }

    func testRejectsEveryEnergyModelChannelOfM6() {
        for c in m6EnergyModel {
            XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: "", name: c.name, unit: c.unit), c.name)
        }
    }

    func testRejectsAneDramAndCPUResidencyChannels() {
        XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: "", name: "ANE", unit: "mJ"))
        XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: "", name: "DRAM0", unit: "mJ"))
        for c in m6CPUStats {
            XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "CPU Stats", subGroup: c.sub, name: c.name, unit: "24Mticks"), c.name)
        }
        // Same name in another group is not an energy counter.
        XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "CPU Stats", subGroup: "", name: "CPU Energy", unit: "mJ"))
    }

    func testIgnoresChannelWithUnknownUnit() {
        XCTAssertFalse(SoCMetrics.isCPUEnergyChannel(group: "Energy Model", subGroup: "", name: "CPU Energy", unit: "24Mticks"))
        XCTAssertNil(SoCMetrics.joulesIfKnown(5, unit: "24Mticks"))
    }

    func testConvertsUnits() {
        XCTAssertEqual(SoCMetrics.joulesIfKnown(1500, unit: "mJ")!, 1.5, accuracy: 1e-12)
        XCTAssertEqual(SoCMetrics.joulesIfKnown(2_000_000, unit: "uJ")!, 2.0, accuracy: 1e-12)
        XCTAssertEqual(SoCMetrics.joulesIfKnown(3_000_000_000, unit: "nJ")!, 3.0, accuracy: 1e-12)
    }

    func testCPUJoulesSumsMatchingChannelsOnly() {
        let channels: [(group: String, subGroup: String?, name: String, unit: String, value: Int64)] = [
            ("Energy Model", "", "CPU Energy", "mJ", 2000),      // 2 J
            ("Energy Model", "", "GPU Energy", "nJ", 9_000_000_000),
            ("Energy Model", "", "CPU Energy", "uJ", 500_000),   // 0.5 J
            ("Energy Model", "", "CPU Energy", "bogus", 7),      // unknown unit: ignored, not 0
        ]
        XCTAssertEqual(SoCMetrics.cpuJoules(channels)!, 2.5, accuracy: 1e-12)
    }

    func testCPUJoulesIsNilWhenNothingMatches() {
        let channels = m6EnergyModel.map { (group: "Energy Model", subGroup: "" as String?, name: $0.name, unit: $0.unit, value: Int64(1000)) }
        XCTAssertNil(SoCMetrics.cpuJoules(channels))
        XCTAssertNil(SoCMetrics.cpuJoules([]))
    }
}
