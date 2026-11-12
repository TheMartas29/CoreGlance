import XCTest
@testable import CoreGlance

final class CoreKindsTests: XCTestCase {
    private func entries(_ spec: [(String, Int)]) -> [(clusterType: String, logicalID: Int)] {
        spec.map { (clusterType: $0.0, logicalID: $0.1) }
    }

    func testResearchInputWithMiddleTierMapsToPerformance() {
        // RESEARCH.md (M6): logical-cpu-id 0–5 = E, 6–7 = P, 8–11 = M, 12 jader.
        let e = entries((0...5).map { ("E", $0) } + (6...7).map { ("P", $0) } + (8...11).map { ("M", $0) })
        let k = CPULoad.kinds(entries: e, count: 12, perflevel: nil)
        XCTAssertEqual(k, Array(repeating: .efficiency, count: 6) + Array(repeating: .performance, count: 6))
    }

    func testUnknownClusterTypeStaysUnknownOthersCorrect() {
        let k = CPULoad.kinds(entries: entries([("E", 0), ("X", 1), ("P", 2)]), count: 3, perflevel: nil)
        XCTAssertEqual(k, [.efficiency, .unknown, .performance])
    }

    func testLogicalIDBeyondCountIsIgnored() {
        let k = CPULoad.kinds(entries: entries([("E", 0), ("P", 1), ("P", 5), ("E", -1)]), count: 2, perflevel: nil)
        XCTAssertEqual(k, [.efficiency, .performance])
    }

    func testEmptyEntriesFallBackToPerflevel() {
        let k = CPULoad.kinds(entries: [], count: 8, perflevel: (p: 4, e: 4))
        XCTAssertEqual(k, Array(repeating: .efficiency, count: 4) + Array(repeating: .performance, count: 4))
    }

    func testEmptyEntriesWithoutPerflevelAreUnknown() {
        XCTAssertEqual(CPULoad.kinds(entries: [], count: 4, perflevel: nil), Array(repeating: .unknown, count: 4))
    }

    func testPerflevelNotMatchingCountIsUnknown() {
        XCTAssertEqual(CPULoad.kinds(entries: [], count: 8, perflevel: (p: 4, e: 2)), Array(repeating: .unknown, count: 8))
    }

    func testOnlyEAndPKeepsPreviousBehavior() {
        // Dosavadní chování: E -> efficiency, P -> performance, nepopsaná jádra unknown; perflevel se ignoruje.
        let k = CPULoad.kinds(entries: entries([("E", 0), ("E", 1), ("P", 2), ("P", 3)]), count: 5, perflevel: (p: 3, e: 2))
        XCTAssertEqual(k, [.efficiency, .efficiency, .performance, .performance, .unknown])
    }
}
