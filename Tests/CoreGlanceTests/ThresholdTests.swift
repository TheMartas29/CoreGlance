import XCTest
@testable import CoreGlance

final class ThresholdTests: XCTestCase {
    func testSeverityAtBoundaries() {
        let t = Threshold(warning: 90, critical: 100)
        XCTAssertEqual(t.severity(of: 89.9), .normal)
        XCTAssertEqual(t.severity(of: 90), .warning)
        XCTAssertEqual(t.severity(of: 99.9), .warning)
        XCTAssertEqual(t.severity(of: 100), .critical)
        XCTAssertEqual(t.severity(of: 120), .critical)
    }

    func testDefaultThresholds() {
        XCTAssertEqual(Metric.cpuTemperature.defaultThreshold, Threshold(warning: 90, critical: 100))
        XCTAssertEqual(Metric.gpuTemperature.defaultThreshold, Threshold(warning: 85, critical: 100))
        XCTAssertEqual(Metric.batteryTemperature.defaultThreshold, Threshold(warning: 35, critical: 40))
        XCTAssertEqual(Metric.ssdTemperature.defaultThreshold, Threshold(warning: 70, critical: 80))
        XCTAssertNil(Metric.cpu.defaultThreshold)  // only temperatures are colored
    }

    func testDefaultsClassifyBatteryAndSsd() throws {
        let battery = try XCTUnwrap(Metric.batteryTemperature.defaultThreshold)
        XCTAssertEqual(battery.severity(of: 34.9), .normal)
        XCTAssertEqual(battery.severity(of: 35), .warning)
        XCTAssertEqual(battery.severity(of: 40), .critical)
        let ssd = try XCTUnwrap(Metric.ssdTemperature.defaultThreshold)
        XCTAssertEqual(ssd.severity(of: 69), .normal)
        XCTAssertEqual(ssd.severity(of: 70), .warning)
        XCTAssertEqual(ssd.severity(of: 80), .critical)
    }
}
