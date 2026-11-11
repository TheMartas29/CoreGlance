import XCTest
@testable import CoreGlance

final class ThermalsTests: XCTestCase {
    func testClassifyARM() {
        let c = Thermals.classify(keys: ["Tp0a", "Te07", "Tg01", "TB0T", "TH0x", "TA0P", "TB0X"], isARM: true)
        XCTAssertEqual(c.cpu, ["Tp0a", "Te07"])
        XCTAssertEqual(c.gpu, ["Tg01"])
        XCTAssertEqual(c.battery, ["TB0T"])
        XCTAssertEqual(c.ssd, ["TH0x"])
    }

    func testClassifyIntel() {
        let c = Thermals.classify(keys: ["TC0P", "TC0C", "TG0P", "TH0a", "TH0b", "TH0A", "TH0x", "Tp0a"], isARM: false)
        XCTAssertEqual(c.cpu, ["TC0P", "TC0C"])
        XCTAssertEqual(c.gpu, ["TG0P"])
        XCTAssertEqual(c.ssd, ["TH0a", "TH0b", "TH0A", "TH0x"])
        XCTAssertTrue(c.battery.isEmpty)
    }

    func testAggregateDropsOutOfRange() throws {
        // 5 and 150 are outside 10...120; mean of 40 and 60 is 50 (hand-computed).
        let r = try XCTUnwrap(Thermals.aggregate([5, 40, 60, 150], valid: 10...120))
        XCTAssertEqual(r.average, 50, accuracy: 0.0001)
        XCTAssertEqual(r.max, 60, accuracy: 0.0001)
    }

    func testAggregateNilWhenNoValidValue() {
        XCTAssertNil(Thermals.aggregate([], valid: 10...120))
        XCTAssertNil(Thermals.aggregate([5, 150], valid: 10...120))
    }
}
