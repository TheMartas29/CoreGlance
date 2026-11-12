import XCTest
@testable import CoreGlance

final class DumpFormatTests: XCTestCase {
    func testChannelLineWithEmptySubgroup() {
        XCTAssertEqual(DumpFormat.channelLine(group: "Energy Model", subGroup: "", name: "GPU Energy", unit: "mJ"),
                       "ioreport channel: group=\"Energy Model\" subgroup=\"\" name=\"GPU Energy\" unit=\"mJ\"")
    }

    func testChannelLineKeepsSubgroup() {
        XCTAssertEqual(DumpFormat.channelLine(group: "CPU Stats", subGroup: "CPU Core Performance States", name: "ECPU0", unit: "24Mticks"),
                       "ioreport channel: group=\"CPU Stats\" subgroup=\"CPU Core Performance States\" name=\"ECPU0\" unit=\"24Mticks\"")
    }

    func testCoreLine() {
        XCTAssertEqual(DumpFormat.coreLine(id: 8, clusterType: "M"), "cpu8 cluster-type=M logical-cpu-id=8")
    }

    func testCoreLineMissingValuesPrintQuestionMark() {
        XCTAssertEqual(DumpFormat.coreLine(id: nil, clusterType: nil), "cpu? cluster-type=? logical-cpu-id=?")
        XCTAssertEqual(DumpFormat.coreLine(id: 3, clusterType: ""), "cpu3 cluster-type=? logical-cpu-id=3")
    }
}
