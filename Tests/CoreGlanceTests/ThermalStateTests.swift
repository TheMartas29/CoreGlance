import XCTest
@testable import CoreGlance

final class ThermalStateTests: XCTestCase {
    // Expected values come from the ticket (coreglance#9), not from the code:
    // nominal → normal, fair → warning, serious/critical → critical; the bar text is short, the popover text full.
    func testMappingTable() {
        let table: [(ProcessInfo.ThermalState, String, String, Severity)] = [
            (.nominal, "OK", "Nominal", .normal),
            (.fair, "FAIR", "Fair", .warning),
            (.serious, "HOT", "Serious", .critical),
            (.critical, "CRIT", "Critical", .critical),
        ]
        for (state, short, full, severity) in table {
            let level = ThermalLevel(state)
            XCTAssertEqual(level.shortText, short)
            XCTAssertEqual(level.fullName, full)
            XCTAssertEqual(level.severity, severity)
        }
    }

    func testUnknownRawValueIsDashAndNormal() throws {
        let future = try XCTUnwrap(ProcessInfo.ThermalState(rawValue: 99))
        let level = ThermalLevel(future)
        XCTAssertEqual(level.shortText, "–")
        XCTAssertEqual(level.fullName, "–")
        XCTAssertEqual(level.severity, .normal)
    }

    func testMonitorReadsInjectedSource() {
        let expected: [(ProcessInfo.ThermalState, ThermalLevel)] = [
            (.nominal, .nominal), (.fair, .fair), (.serious, .serious), (.critical, .critical),
        ]
        for (state, level) in expected {
            let monitor = Monitor(thermalSource: { state })
            XCTAssertEqual(monitor.readNow().thermalState, level)
        }
    }

    func testMetricDefinitions() {
        let m = Metric.thermalState
        XCTAssertEqual(m.group, .system)
        XCTAssertFalse(m.title.isEmpty)
        XCTAssertFalse(m.symbol.isEmpty)
        XCTAssertFalse(m.caption.isEmpty)
        XCTAssertTrue(m.isAvailable(in: Snapshot()))
        var sampled = Snapshot()
        sampled.sampled = true
        XCTAssertTrue(m.isAvailable(in: sampled))
        for metric in Metric.allCases {
            XCTAssertFalse(metric.title.isEmpty)
            XCTAssertFalse(metric.symbol.isEmpty)
            XCTAssertFalse(metric.caption.isEmpty)
        }
    }

    func testOffByDefaultAndOldSettingsKeepTheirSelection() {
        XCTAssertFalse(Preferences.initialMetrics(stored: nil).contains(.thermalState))
        // A list saved by 0.2.x (no thermalState) loads unchanged, in catalogue order.
        let old = ["fan", "cpu", "battery"]
        XCTAssertEqual(Preferences.initialMetrics(stored: old), [.cpu, .battery, .fan])
        // Unknown names from other versions are dropped without breaking the rest.
        XCTAssertEqual(Preferences.initialMetrics(stored: ["cpu", "bogus"]), [.cpu])
        // Once enabled, it is kept.
        XCTAssertEqual(Preferences.initialMetrics(stored: ["thermalState", "cpu"]), [.cpu, .thermalState])
    }

    func testReadmeStatesTheRealMetricCount() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let readme = try String(contentsOf: root.appendingPathComponent("README.md"), encoding: .utf8)
        XCTAssertEqual(Metric.allCases.count, 20)  // 19 original metrics + thermal state
        XCTAssertTrue(readme.contains("any combination of 20 metrics"))
    }

    func testBarSeverityAndValueFollowThermalState() {
        let suite = "CoreGlanceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Preferences(defaults: defaults)
        let expected: [(ThermalLevel, String, Severity)] = [
            (.nominal, "OK", .normal), (.fair, "FAIR", .warning), (.serious, "HOT", .critical), (.critical, "CRIT", .critical),
        ]
        for (level, text, severity) in expected {
            var s = Snapshot()
            s.thermalState = level
            XCTAssertEqual(StatusBarRenderer.severity(for: .thermalState, in: s, prefs: prefs), severity)
            XCTAssertEqual(StatusBarRenderer.value(for: .thermalState, in: s, prefs: prefs), text)
        }
    }
}
