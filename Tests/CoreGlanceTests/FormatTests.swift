import XCTest
@testable import CoreGlance

/// Pure formatting; the temperature unit is always passed explicitly so
/// `Preferences.shared` (UserDefaults.standard) is never touched.
final class FormatTests: XCTestCase {
    func testPercent() {
        XCTAssertEqual(Format.percent(0.456), "46%")
        XCTAssertEqual(Format.percent(0), "0%")
        XCTAssertEqual(Format.percent(1), "100%")
        XCTAssertEqual(Format.percent(nil), "–")
        XCTAssertEqual(Format.percent(0.05, width: 3), "\u{2007}\u{2007}5%")  // figure-space padding
    }

    func testTemperatureCelsiusAndFahrenheit() {
        XCTAssertEqual(Format.temperature(nil, .celsius), "–")
        XCTAssertEqual(Format.temperature(nil, .fahrenheit), "–")
        XCTAssertEqual(Format.temperature(45.4, .celsius), "45°")
        XCTAssertEqual(Format.temperature(0, .fahrenheit), "32°")
        XCTAssertEqual(Format.temperature(100, .fahrenheit), "212°")
        XCTAssertEqual(Format.temperature(-40, .fahrenheit), "-40°")
    }

    func testGhzAndMhz() {
        XCTAssertEqual(Format.ghz(3204), "3.20 GHz")
        XCTAssertEqual(Format.ghz(nil), "–")
        XCTAssertEqual(Format.ghz(0), "–")
        XCTAssertEqual(Format.mhz(1398.6), "1399 MHz")
        XCTAssertEqual(Format.mhz(nil), "–")
    }

    func testGigabytes() {
        XCTAssertEqual(Format.gigabytes(8 * 1_073_741_824), "8.0 GB")
        XCTAssertEqual(Format.gigabytes(1_610_612_736), "1.5 GB")  // 1.5 GiB
        XCTAssertEqual(Format.gigabytes(0), "0.0 GB")
    }

    func testWatts() {
        XCTAssertEqual(Format.watts(nil), "–")
        XCTAssertEqual(Format.watts(5.234), "5.23 W")
        XCTAssertEqual(Format.watts(9.99), "9.99 W")
        XCTAssertEqual(Format.watts(10), "10.0 W")
        XCTAssertEqual(Format.watts(12.34), "12.3 W")
    }

    func testRateBoundaries() {
        XCTAssertEqual(Format.rate(0), "0B")
        XCTAssertEqual(Format.rate(999), "999B")       // below 1000 stays in bytes
        XCTAssertEqual(Format.rate(1000), "1.0K")      // 1000 switches unit, divides by 1024 -> 0.98
        XCTAssertEqual(Format.rate(1024), "1.0K")
        XCTAssertEqual(Format.rate(1536), "1.5K")
        XCTAssertEqual(Format.rate(10_240), "10K")     // >= 10 drops the decimal
        XCTAssertEqual(Format.rate(1_048_576), "1.0M")
        XCTAssertEqual(Format.rate(1_073_741_824), "1.0G")
    }

    func testDuration() {
        XCTAssertNil(Format.duration(minutes: nil))
        XCTAssertEqual(Format.duration(minutes: 0), "0:00")
        XCTAssertEqual(Format.duration(minutes: 5), "0:05")
        XCTAssertEqual(Format.duration(minutes: 90), "1:30")
        XCTAssertEqual(Format.duration(minutes: 600), "10:00")
    }
}
