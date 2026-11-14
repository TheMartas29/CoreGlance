import XCTest
@testable import CoreGlance

final class RateHistoryTests: XCTestCase {
    func testRecordStoresNetworkRates() {
        var hs = Histories()
        var s = Snapshot()
        s.network = NetworkStats(down: 2_000_000, up: 150_000)
        hs.record(s, at: 1)
        XCTAssertEqual(hs.networkDown.values, [2_000_000])
        XCTAssertEqual(hs.networkUp.values, [150_000])
    }

    func testRecordStoresDiskRatesOnlyWhenAvailable() {
        var hs = Histories()
        var s = Snapshot()
        s.diskIO = nil
        hs.record(s, at: 1)
        XCTAssertTrue(hs.diskRead.samples.isEmpty)
        XCTAssertTrue(hs.diskWrite.samples.isEmpty)

        s.diskIO = DiskIOStats(read: 1_600_000, write: 51_000)
        hs.record(s, at: 2)
        XCTAssertEqual(hs.diskRead.values, [1_600_000])
        XCTAssertEqual(hs.diskWrite.values, [51_000])
    }

    func testRateRangeStartsAtZeroAndHasMinimumSpan() {
        XCTAssertEqual(Sparkline.rateRange([]), 0...100_000)
        XCTAssertEqual(Sparkline.rateRange([5_000]), 0...100_000) // 5 kB/s noise, not a spike
        XCTAssertEqual(Sparkline.minimumRateSpan, 100_000)
    }

    func testRateRangeGrowsWithPeak() {
        XCTAssertEqual(Sparkline.rateRange([1_000, 3_500_000, 20]), 0...3_500_000)
    }

    func testRateRangeSharesMaximumAcrossPair() {
        let r = Sparkline.rateRange([10_000, 20_000], [4_000_000])
        XCTAssertEqual(r, 0...4_000_000)
        XCTAssertEqual(Sparkline.rateRange([4_000_000], [10_000, 20_000]), r)
        XCTAssertEqual(Sparkline.rateRange([], []), 0...100_000)
    }

    func testRateRangeIgnoresNegativeAndNonFinite() {
        XCTAssertEqual(Sparkline.rateRange([-5, .nan, .infinity, 300_000]), 0...300_000)
    }

    func testRateGraphsVisibilityFollowsToggleAndAvailability() {
        XCTAssertTrue(Sparkline.showsRateGraph(showHistory: true, available: true))
        XCTAssertFalse(Sparkline.showsRateGraph(showHistory: false, available: true))
        XCTAssertFalse(Sparkline.showsRateGraph(showHistory: true, available: false))
    }

    func testGraphTintsMeetGraphicalContrastInBothAppearances() {
        let tints: [(String, RGB, RGB)] = [
            ("down/read", GraphPalette.lightPrimary, GraphPalette.darkPrimary),
            ("up/write", GraphPalette.lightSecondary, GraphPalette.darkSecondary),
        ]
        for (name, light, dark) in tints {
            XCTAssertGreaterThanOrEqual(contrastRatio(light, WarningPalette.lightBackground), 3, "\(name) light")
            XCTAssertGreaterThanOrEqual(contrastRatio(dark, WarningPalette.darkBackground), 3, "\(name) dark")
        }
    }
}
