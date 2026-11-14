import XCTest
@testable import CoreGlance

final class HistoryTests: XCTestCase {
    func testAppendDropsSamplesOlderThanWindow() {
        var h = History()
        h.append(0.1, at: 0)
        h.append(0.2, at: 100)
        h.append(0.3, at: 301) // window 300 s: the sample at t=0 is now 301 s old
        XCTAssertEqual(h.values, [0.2, 0.3])
    }

    func testSampleExactlyAtWindowEdgeIsKept() {
        var h = History()
        h.append(0.1, at: 0)
        h.append(0.2, at: 300)
        XCTAssertEqual(h.values, [0.1, 0.2])
    }

    func testCountIsBoundedAtOneSecondInterval() {
        var h = History()
        for i in 0..<10_000 { h.append(Double(i), at: TimeInterval(i)) }
        XCTAssertLessThanOrEqual(h.samples.count, History.capacity)
        // 1 s interval: the newest 301 samples (t = 9699...9999) fit into the 300 s window.
        XCTAssertEqual(h.samples.count, 301)
        XCTAssertEqual(h.samples.first?.value, 9699)
        XCTAssertEqual(h.samples.last?.value, 9999)
    }

    func testCapacityCapsSubSecondIntervals() {
        var h = History()
        for i in 0..<10_000 { h.append(Double(i), at: Double(i) * 0.01) } // 100 Hz, 100 s in total
        XCTAssertEqual(h.samples.count, History.capacity)
        XCTAssertEqual(h.samples.last?.value, 9999)
        XCTAssertEqual(h.samples.first?.value, Double(10_000 - History.capacity))
    }

    func testMissingValueIsNotStored() {
        var h = History()
        h.append(nil, at: 0)
        h.append(.nan, at: 1)
        h.append(.infinity, at: 2)
        XCTAssertTrue(h.samples.isEmpty)
        h.append(0.5, at: 3)
        h.append(nil, at: 4)
        XCTAssertEqual(h.values, [0.5])
    }

    func testRecordSkipsSensorsThatDoNotExist() {
        var hs = Histories()
        var s = Snapshot()
        s.cpu = 0.25
        s.gpu = nil
        s.memory.used = 8
        s.memory.total = 16
        s.thermals.cpu = nil
        hs.record(s, at: 10)
        XCTAssertEqual(hs.cpu.values, [0.25])
        XCTAssertEqual(hs.memory.values, [0.5])
        XCTAssertTrue(hs.gpu.samples.isEmpty)
        XCTAssertTrue(hs.cpuTemperature.samples.isEmpty)

        s.gpu = 0.4
        s.thermals.cpu = Reading(average: 61.5, max: 70)
        hs.record(s, at: 12)
        XCTAssertEqual(hs.gpu.values, [0.4])
        XCTAssertEqual(hs.cpuTemperature.values, [61.5])
    }

    func testRecordIgnoresMemoryWithUnknownTotal() {
        var hs = Histories()
        hs.record(Snapshot(), at: 0) // total 0 → no division by zero
        XCTAssertTrue(hs.memory.samples.isEmpty)
    }
}

final class SparklineTests: XCTestCase {
    private func s(_ t: Double, _ v: Double) -> HistorySample { HistorySample(time: t, value: v) }

    func testEmptySeriesGivesNoPoints() {
        XCTAssertTrue(Sparkline.points([], now: 100, range: Sparkline.percentRange).isEmpty)
    }

    func testSinglePoint() {
        let p = Sparkline.points([s(100, 0.5)], now: 100, range: 0...1)
        XCTAssertEqual(p.count, 1)
        XCTAssertEqual(p[0].x, 1, accuracy: 1e-9)
        XCTAssertEqual(p[0].y, 0.5, accuracy: 1e-9)
    }

    func testSeriesWithRange() {
        // 150 s ago is the middle of the 300 s window; 25 % of 0...1 is a quarter of the height.
        let p = Sparkline.points([s(0, 0), s(150, 0.25), s(300, 1)], now: 300, range: 0...1)
        XCTAssertEqual(p.map(\.x), [0, 0.5, 1])
        XCTAssertEqual(p.map(\.y), [0, 0.25, 1])
    }

    func testConstantSeriesWithAutoRangeIsCentred() {
        let values = [55.0, 55, 55]
        let r = Sparkline.autoRange(values)
        let p = Sparkline.points(values.enumerated().map { s(Double($0.offset), $0.element) }, now: 2, range: r)
        XCTAssertEqual(p.map(\.y), [0.5, 0.5, 0.5])
    }

    func testDegenerateRangeDoesNotDivideByZero() {
        let p = Sparkline.points([s(0, 3)], now: 0, range: 3...3)
        XCTAssertEqual(p[0].y, 0.5)
    }

    func testOutOfRangeValuesAreClamped() {
        let p = Sparkline.points([s(10, 1.7), s(11, -0.3)], now: 11, range: 0...1)
        XCTAssertEqual(p.map(\.y), [1, 0])
    }

    func testSamplesOlderThanWindowAreClampedToLeftEdge() {
        let p = Sparkline.points([s(0, 0.5)], now: 1000, range: 0...1)
        XCTAssertEqual(p[0].x, 0)
    }

    func testTemperatureRangeHasMinimumSpanOf10() {
        // 0.5 °C noise must stay a tiny wiggle: 60.0 ... 60.5 on a 10 °C scale.
        let r = Sparkline.autoRange([60.0, 60.5, 60.2])
        XCTAssertEqual(r.upperBound - r.lowerBound, 10, accuracy: 1e-9)
        XCTAssertEqual(r.lowerBound, 55.25, accuracy: 1e-9)
        let p = Sparkline.points([s(0, 60.0), s(1, 60.5)], now: 1, range: r)
        XCTAssertEqual(p[1].y - p[0].y, 0.05, accuracy: 1e-9)
    }

    func testTemperatureRangeGrowsWithWideData() {
        let r = Sparkline.autoRange([40, 80])
        XCTAssertEqual(r.lowerBound, 40, accuracy: 1e-9)
        XCTAssertEqual(r.upperBound, 80, accuracy: 1e-9)
    }

    func testUsageUsesFixedFullScale() {
        XCTAssertEqual(Sparkline.percentRange, 0...1)
    }
}
