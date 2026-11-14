import XCTest
@testable import CoreGlance

private final class FakeNotifier: AlertNotifier {
    var delivered: [(title: String, body: String)] = []
    var authRequests = 0
    func requestAuthorization(completion: @escaping (Bool) -> Void) { authRequests += 1; completion(true) }
    func deliver(title: String, body: String) { delivered.append((title, body)) }
}

final class AlertTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func cpu(_ s: Severity, _ c: Double = 101) -> [TemperatureReading] {
        [TemperatureReading(metric: .cpuTemperature, celsius: c, severity: s)]
    }

    // MARK: AlertTracker

    func testEntryToCriticalSendsOnceAndStayingSendsNothing() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: cpu(.warning, 92), thermalState: .nominal, now: t0), [])
        XCTAssertEqual(tr.update(temperatures: cpu(.critical, 101), thermalState: .nominal, now: t0 + 2),
                       [.temperatureCritical(.cpuTemperature, celsius: 101)])
        XCTAssertEqual(tr.update(temperatures: cpu(.critical, 103), thermalState: .nominal, now: t0 + 4), [])
        XCTAssertEqual(tr.update(temperatures: cpu(.critical, 103), thermalState: .nominal, now: t0 + 3600), [])
    }

    func testReentryWithinTenMinutesIsSuppressedAfterwardsSent() {
        var tr = AlertTracker()
        _ = tr.update(temperatures: cpu(.critical), thermalState: .nominal, now: t0)
        _ = tr.update(temperatures: cpu(.normal, 60), thermalState: .nominal, now: t0 + 60)
        // 5 minutes after the first notification: too early.
        XCTAssertEqual(tr.update(temperatures: cpu(.critical), thermalState: .nominal, now: t0 + 300), [])
        _ = tr.update(temperatures: cpu(.normal, 60), thermalState: .nominal, now: t0 + 400)
        // Exactly 10 minutes (600 s) after the notification: allowed.
        XCTAssertEqual(tr.update(temperatures: cpu(.critical, 105), thermalState: .nominal, now: t0 + 600),
                       [.temperatureCritical(.cpuTemperature, celsius: 105)])
    }

    func testCooldownIsPerMetric() {
        var tr = AlertTracker()
        _ = tr.update(temperatures: cpu(.critical), thermalState: .nominal, now: t0)
        let ssd = TemperatureReading(metric: .ssdTemperature, celsius: 81, severity: .critical)
        XCTAssertEqual(tr.update(temperatures: cpu(.critical) + [ssd], thermalState: .nominal, now: t0 + 30),
                       [.temperatureCritical(.ssdTemperature, celsius: 81)])
    }

    func testMissingReadingCountsAsNotCritical() {
        var tr = AlertTracker()
        _ = tr.update(temperatures: cpu(.critical), thermalState: .nominal, now: t0)
        _ = tr.update(temperatures: [], thermalState: .nominal, now: t0 + 10)
        XCTAssertEqual(tr.update(temperatures: cpu(.critical), thermalState: .nominal, now: t0 + 700).count, 1)
    }

    func testThermalStateRisesNotifyFallsDoNot() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .fair, now: t0), [])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .serious, now: t0 + 2), [.thermalState(.serious)])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .serious, now: t0 + 4), [])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0 + 6), [.thermalState(.critical)])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .serious, now: t0 + 8), [])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .nominal, now: t0 + 10), [])
    }

    func testStartingInCriticalSendsOnce() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0), [.thermalState(.critical)])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0 + 2), [])
    }

    func testUnknownThermalStateNeverNotifies() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .unknown, now: t0), [])
    }

    // MARK: AlertMessage

    func testTemperatureMessageCelsiusAndFahrenheit() {
        // 101 °C = 213.8 °F (101 × 9/5 + 32), shown rounded as 214.
        let e = AlertEvent.temperatureCritical(.cpuTemperature, celsius: 101)
        let c = AlertMessage.make(e, unit: .celsius)
        XCTAssertEqual(c.title, "CPU temperature is critical")
        XCTAssertEqual(c.body, "CPU temperature reached 101 °C (critical level).")
        let f = AlertMessage.make(e, unit: .fahrenheit)
        XCTAssertEqual(f.body, "CPU temperature reached 214 °F (critical level).")
    }

    func testOtherMetricNamesInMessage() {
        let m = AlertMessage.make(.temperatureCritical(.batteryTemperature, celsius: 41), unit: .celsius)
        XCTAssertEqual(m.title, "Battery temperature is critical")
        XCTAssertTrue(m.body.contains("41 °C"))
    }

    func testThermalStateMessage() {
        let s = AlertMessage.make(.thermalState(.serious), unit: .fahrenheit)
        XCTAssertEqual(s.title, "Thermal state: Serious")
        XCTAssertEqual(s.body, "macOS reports a serious thermal state; the Mac may slow down to cool off.")
        XCTAssertEqual(AlertMessage.make(.thermalState(.critical), unit: .celsius).title, "Thermal state: Critical")
    }

    // MARK: AlertCoordinator

    private func prefs(notify: Bool) -> Preferences {
        let suite = "CoreGlanceAlertTests"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        let p = Preferences(defaults: d)
        p.notifyOnCritical = notify
        return p
    }

    private func hotSnapshot() -> Snapshot {
        var s = Snapshot()
        s.sampled = true
        s.thermals.ssd = 85          // default SSD critical is 80 °C
        s.thermalState = .serious
        return s
    }

    func testCoordinatorDoesNothingWhenSwitchIsOff() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        c.process(hotSnapshot(), prefs: prefs(notify: false), now: t0)
        XCTAssertTrue(fake.delivered.isEmpty)
        XCTAssertEqual(fake.authRequests, 0)
    }

    func testCoordinatorDeliversTemperatureAndThermalWhenOn() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        let p = prefs(notify: true)
        c.process(hotSnapshot(), prefs: p, now: t0)
        XCTAssertEqual(fake.delivered.map(\.title), ["SSD temperature is critical", "Thermal state: Serious"])
        c.process(hotSnapshot(), prefs: p, now: t0 + 2)
        XCTAssertEqual(fake.delivered.count, 2)
    }

    func testCoordinatorUsesCustomThreshold() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        let p = prefs(notify: true)
        p.setThreshold(.ssdTemperature, Threshold(warning: 90, critical: 95))
        c.process(hotSnapshot(), prefs: p, now: t0)   // 85 °C is below the custom critical 95 °C
        XCTAssertEqual(fake.delivered.map(\.title), ["Thermal state: Serious"])
    }

    func testCoordinatorIgnoresUnsampledSnapshot() {
        let fake = FakeNotifier()
        var s = hotSnapshot()
        s.sampled = false
        AlertCoordinator(notifier: fake).process(s, prefs: prefs(notify: true), now: t0)
        XCTAssertTrue(fake.delivered.isEmpty)
    }

    // MARK: Preferences key

    func testNotifyOnCriticalDefaultsOffAndPersists() {
        let suite = "CoreGlanceAlertPrefs"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        defer { d.removePersistentDomain(forName: suite) }
        XCTAssertFalse(Preferences(defaults: d).notifyOnCritical)
        let p = Preferences(defaults: d)
        p.notifyOnCritical = true
        XCTAssertTrue(d.bool(forKey: "notifyOnCritical"))
        XCTAssertTrue(Preferences(defaults: d).notifyOnCritical)
    }
}
