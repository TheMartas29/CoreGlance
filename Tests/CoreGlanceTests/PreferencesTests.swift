import XCTest
@testable import CoreGlance

/// Persistence of user settings. Every test uses its own UserDefaults suite (never `.standard`,
/// never `Preferences.shared`) and removes it in tearDown.
final class PreferencesTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName = ""

    override func setUpWithError() throws {
        suiteName = "coreglance.tests.prefs.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
    }

    func testDefaultsOfEmptyStore() {
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.interval, 2)
        XCTAssertTrue(p.showGlyphs)
        XCTAssertTrue(p.showCaptions)
        XCTAssertFalse(p.memoryAsPercent)
        XCTAssertEqual(p.unit, .celsius)
        XCTAssertEqual(p.temperatureMode, .average)
        XCTAssertEqual(p.font, .system)
        XCTAssertTrue(p.colorize)
        XCTAssertEqual(p.enabled, [.cpu, .cpuTemperature, .gpu, .memory, .batteryTemperature])
        XCTAssertTrue(p.customThresholds.isEmpty)
    }

    func testAllPublishedFieldsRoundTrip() {
        let first = Preferences(defaults: defaults)
        first.enabled = [.cpu, .fan, .network]
        first.interval = 5
        first.showGlyphs = false
        first.showCaptions = false
        first.memoryAsPercent = true
        first.unit = .fahrenheit
        first.temperatureMode = .hottest
        first.font = .monospaced
        first.colorize = false

        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.enabled, [.cpu, .fan, .network])
        XCTAssertEqual(again.interval, 5)
        XCTAssertFalse(again.showGlyphs)
        XCTAssertFalse(again.showCaptions)
        XCTAssertTrue(again.memoryAsPercent)
        XCTAssertEqual(again.unit, .fahrenheit)
        XCTAssertEqual(again.temperatureMode, .hottest)
        XCTAssertEqual(again.font, .monospaced)
        XCTAssertFalse(again.colorize)
    }

    func testSetKeepsCatalogueOrderWhenEnablingAndDisabling() {
        let p = Preferences(defaults: defaults)
        p.enabled = [.cpu, .memory]
        p.set(.gpu, true)                    // between cpu and memory in Metric.allCases
        XCTAssertEqual(p.enabled, [.cpu, .gpu, .memory])
        p.set(.cpuCores, true)               // right after cpu
        XCTAssertEqual(p.enabled, [.cpu, .cpuCores, .gpu, .memory])
        p.set(.gpu, false)
        XCTAssertEqual(p.enabled, [.cpu, .cpuCores, .memory])
        XCTAssertEqual(Preferences(defaults: defaults).enabled, [.cpu, .cpuCores, .memory])
    }

    func testEnablingTwiceDoesNotDuplicate() {
        let p = Preferences(defaults: defaults)
        p.enabled = [.cpu]
        p.set(.network, true)
        p.set(.network, true)
        XCTAssertEqual(p.enabled, [.cpu, .network])
        p.set(.fan, false)                   // disabling something not enabled is a no-op
        XCTAssertEqual(p.enabled, [.cpu, .network])
    }

    func testThresholdEqualToDefaultIsNotStored() {
        let p = Preferences(defaults: defaults)
        p.setThreshold(.cpuTemperature, Threshold(warning: 90, critical: 100))   // the default
        XCTAssertTrue(p.customThresholds.isEmpty)
        XCTAssertTrue(Preferences(defaults: defaults).customThresholds.isEmpty)
    }

    func testCustomThresholdSurvivesRestartAndResetClearsIt() {
        let p = Preferences(defaults: defaults)
        p.setThreshold(.cpuTemperature, Threshold(warning: 80, critical: 95))
        XCTAssertEqual(p.customThresholds, [.cpuTemperature: Threshold(warning: 80, critical: 95)])

        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.threshold(.cpuTemperature), Threshold(warning: 80, critical: 95))
        XCTAssertEqual(again.threshold(.gpuTemperature), Threshold(warning: 85, critical: 100))

        again.resetThresholds()
        XCTAssertTrue(again.customThresholds.isEmpty)
        let afterReset = Preferences(defaults: defaults)
        XCTAssertTrue(afterReset.customThresholds.isEmpty)
        XCTAssertEqual(afterReset.threshold(.cpuTemperature), Threshold(warning: 90, critical: 100))
    }

    func testUnknownEnumValuesFallBackToDefaults() {
        defaults.set("kelvin", forKey: "unit")
        defaults.set("comic-sans", forKey: "font")
        defaults.set("median", forKey: "temperatureMode")
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.unit, .celsius)
        XCTAssertEqual(p.font, .system)
        XCTAssertEqual(p.temperatureMode, .average)
    }

    func testCorruptedThresholdsAreIgnored() {
        defaults.set([
            "cpuTemperature": [80.0],               // one element
            "gpuTemperature": [1.0, 2.0, 3.0],      // three elements
            "doesNotExist": [70.0, 80.0],           // unknown metric
            "ssdTemperature": [60.0, 75.0],         // valid
        ], forKey: "thresholds")
        let p = Preferences(defaults: defaults)
        XCTAssertEqual(p.customThresholds, [.ssdTemperature: Threshold(warning: 60, critical: 75)])
        XCTAssertEqual(p.threshold(.cpuTemperature), Threshold(warning: 90, critical: 100))
    }

    func testUnknownMetricNamesAreDroppedFromSavedList() {
        defaults.set(["network", "retired-metric", "cpu"], forKey: "metrics")
        XCTAssertEqual(Preferences(defaults: defaults).enabled, [.cpu, .network])
    }

    func testShowHistoryDefaultsOn() {
        XCTAssertTrue(Preferences(defaults: defaults).showHistory)
    }

    func testShowHistoryIsSavedUnderOwnKeyAndLoaded() {
        let first = Preferences(defaults: defaults)
        first.showHistory = false
        XCTAssertEqual(defaults.object(forKey: "showHistory") as? Bool, false)
        XCTAssertFalse(Preferences(defaults: defaults).showHistory)
        first.showHistory = true
        XCTAssertTrue(Preferences(defaults: defaults).showHistory)
    }
}
