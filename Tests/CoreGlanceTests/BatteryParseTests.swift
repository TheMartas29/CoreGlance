import XCTest
@testable import CoreGlance

final class BatteryParseTests: XCTestCase {
    func testApplePercentIsDirect() {
        let b = BatteryReader.parse(["MaxCapacity": 100, "CurrentCapacity": 80])
        XCTAssertTrue(b.present)
        XCTAssertEqual(b.percent, 0.8, accuracy: 1e-9)
    }

    func testIntelPercentIsMahRatio() {
        let b = BatteryReader.parse(["MaxCapacity": 5000, "CurrentCapacity": 2500])
        XCTAssertEqual(b.percent, 0.5, accuracy: 1e-9)
    }

    func testTimeIgnoresCalculatingAndZero() {
        for v in [65535, 0] {
            let charging = BatteryReader.parse(["IsCharging": true, "ExternalConnected": true, "AvgTimeToFull": v])
            XCTAssertNil(charging.minutesRemaining, "AvgTimeToFull \(v)")
            let discharging = BatteryReader.parse(["IsCharging": false, "ExternalConnected": false, "AvgTimeToEmpty": v])
            XCTAssertNil(discharging.minutesRemaining, "AvgTimeToEmpty \(v)")
        }
    }

    func testTimeToFullWhileCharging() {
        let b = BatteryReader.parse(["IsCharging": true, "ExternalConnected": true, "AvgTimeToFull": 90, "AvgTimeToEmpty": 10])
        XCTAssertEqual(b.minutesRemaining, 90)
    }

    func testTimeToEmptyWhileDischarging() {
        let b = BatteryReader.parse(["IsCharging": false, "ExternalConnected": false, "AvgTimeToEmpty": 120, "AvgTimeToFull": 5])
        XCTAssertEqual(b.minutesRemaining, 120)
    }

    func testNoEstimateOnACWithoutCharging() {
        let b = BatteryReader.parse(["IsCharging": false, "ExternalConnected": true, "AvgTimeToFull": 90, "AvgTimeToEmpty": 120])
        XCTAssertNil(b.minutesRemaining)
    }

    func testHealthIsRawMaxOverDesign() {
        // 4200 / 6000 = 0.7
        let b = BatteryReader.parse(["AppleRawMaxCapacity": 4200, "DesignCapacity": 6000])
        XCTAssertEqual(try XCTUnwrap(b.health), 0.7, accuracy: 1e-9)
    }

    func testHealthNilWithoutOrZeroDesign() {
        XCTAssertNil(BatteryReader.parse(["AppleRawMaxCapacity": 4200]).health)
        XCTAssertNil(BatteryReader.parse(["AppleRawMaxCapacity": 4200, "DesignCapacity": 0]).health)
    }

    func testPowerIsVoltageTimesAmperage() {
        // 12.0 V × -1.5 A = -18 W (discharging)
        let b = BatteryReader.parse(["Voltage": 12000, "Amperage": -1500])
        XCTAssertEqual(try XCTUnwrap(b.power), -18, accuracy: 1e-9)
        XCTAssertNil(BatteryReader.parse(["Voltage": 12000]).power)
    }

    func testSystemPowerInOnlyWhenPositive() {
        let on = BatteryReader.parse(["PowerTelemetryData": ["SystemPowerIn": 30000]])
        XCTAssertEqual(try XCTUnwrap(on.systemPowerIn), 30, accuracy: 1e-9)
        XCTAssertNil(BatteryReader.parse(["PowerTelemetryData": ["SystemPowerIn": 0]]).systemPowerIn)
        XCTAssertNil(BatteryReader.parse(["PowerTelemetryData": ["SystemPowerIn": -5]]).systemPowerIn)
    }

    func testNoBatteryDoesNotCrash() {
        XCTAssertFalse(BatteryReader.parse([:]).present)
        let b = BatteryReader.parse(["BatteryInstalled": false, "MaxCapacity": 100, "CurrentCapacity": 80])
        XCTAssertFalse(b.present)
        XCTAssertEqual(b.percent, 0)
    }
}
