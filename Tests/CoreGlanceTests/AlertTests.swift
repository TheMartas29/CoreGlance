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

    func testFlappingSeriousCriticalSendsEachLevelOnlyOnceWithinCooldown() {
        var tr = AlertTracker()
        var all: [AlertEvent] = []
        for (i, level) in [ThermalLevel.serious, .critical, .serious, .critical].enumerated() {
            all += tr.update(temperatures: [], thermalState: level, now: t0 + Double(i) * 3)
        }
        XCTAssertEqual(all, [.thermalState(.serious), .thermalState(.critical)])
    }

    func testEscalationFromNominalToCriticalIsSent() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .nominal, now: t0), [])
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0 + 2), [.thermalState(.critical)])
    }

    func testEscalationSeriousToCriticalAfterLongTimeIsSent() {
        var tr = AlertTracker()
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .serious, now: t0), [.thermalState(.serious)])
        // 11 minutes later no Critical has been sent yet: the escalation goes out.
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0 + 660), [.thermalState(.critical)])
    }

    func testCriticalRepeatsAfterTenMinutesWhenFlapping() {
        var tr = AlertTracker()
        _ = tr.update(temperatures: [], thermalState: .critical, now: t0)
        _ = tr.update(temperatures: [], thermalState: .serious, now: t0 + 60)
        XCTAssertEqual(tr.update(temperatures: [], thermalState: .critical, now: t0 + 600), [.thermalState(.critical)])
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

    // MARK: Memory pressure (1 normal, 2 warning, 4 critical)

    private let gb = 1_073_741_824.0

    private func mem(_ p: Int, now: Date, _ tr: inout AlertTracker, silent: Bool = false) -> [AlertEvent] {
        tr.update(temperatures: [], thermalState: .nominal, memoryPressure: p, memoryUsed: 15 * gb, memoryTotal: 16 * gb, now: now, silent: silent)
    }

    func testMemoryPressureFiresOnlyOnTransitionToCritical() {
        var tr = AlertTracker()
        XCTAssertEqual(mem(1, now: t0, &tr), [])
        XCTAssertEqual(mem(2, now: t0 + 2, &tr), [])
        XCTAssertEqual(mem(4, now: t0 + 4, &tr), [.memoryPressureCritical(used: 15 * gb, total: 16 * gb)])
        XCTAssertEqual(mem(4, now: t0 + 6, &tr), [])
        XCTAssertEqual(mem(4, now: t0 + 7200, &tr), [])
    }

    func testMemoryPressureFlappingRespectsTenMinuteCooldown() {
        var tr = AlertTracker()
        XCTAssertEqual(mem(4, now: t0, &tr).count, 1)
        XCTAssertEqual(mem(2, now: t0 + 60, &tr), [])
        XCTAssertEqual(mem(4, now: t0 + 120, &tr), [])      // 2 minutes after the notification
        XCTAssertEqual(mem(2, now: t0 + 300, &tr), [])
        XCTAssertEqual(mem(4, now: t0 + 599, &tr), [])      // 599 s: still too early
        XCTAssertEqual(mem(2, now: t0 + 599.5, &tr), [])
        XCTAssertEqual(mem(4, now: t0 + 600, &tr).count, 1) // exactly 600 s
    }

    func testMemoryPressureSilentReturnsNothingAndStartsNoCooldown() {
        var tr = AlertTracker()
        XCTAssertEqual(mem(1, now: t0, &tr, silent: true), [])
        XCTAssertEqual(mem(4, now: t0 + 10, &tr, silent: true), [])
        _ = mem(2, now: t0 + 20, &tr, silent: true)
        // The silent critical at t0+10 started no cooldown: a rise right after enabling is announced.
        XCTAssertEqual(mem(4, now: t0 + 30, &tr).count, 1)
    }

    func testMemoryPressureCriticalBeforeSwitchOnIsNotAnnounced() {
        var tr = AlertTracker()
        _ = mem(4, now: t0, &tr, silent: true)
        XCTAssertEqual(mem(4, now: t0 + 60, &tr), [])
        _ = mem(2, now: t0 + 120, &tr)
        XCTAssertEqual(mem(4, now: t0 + 180, &tr).count, 1)
    }

    func testCoordinatorDeliversMemoryPressureOnlyWhenOn() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        var s = Snapshot()
        s.sampled = true
        s.memory.total = 16 * gb
        s.memory.used = 15 * gb
        s.memory.pressure = 4
        c.process(s, prefs: prefs(notify: false), now: t0)
        XCTAssertTrue(fake.delivered.isEmpty)
        s.memory.pressure = 2
        c.process(s, prefs: prefs(notify: true), now: t0 + 10)
        s.memory.pressure = 4
        c.process(s, prefs: prefs(notify: true), now: t0 + 20)
        XCTAssertEqual(fake.delivered.map(\.title), ["Memory pressure is critical"])
    }

    // MARK: AlertMessage

    func testMemoryPressureMessage() {
        // 15 of 16 GB = 94 % (rounded from 93.75).
        let m = AlertMessage.make(.memoryPressureCritical(used: 15 * gb, total: 16 * gb), unit: .celsius)
        XCTAssertEqual(m.title, "Memory pressure is critical")
        XCTAssertEqual(m.body, "macOS reports critical memory pressure: 15.0 of 16.0 GB in use (94 %). Close apps you don't need.")
    }

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

    private func criticalSnapshot() -> Snapshot {
        var s = hotSnapshot()
        s.thermalState = .critical
        return s
    }

    func testCoordinatorDeliversNothingWhileSwitchIsOff() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        let off = prefs(notify: false)
        // A rising sequence (nominal → serious + hot SSD → critical) must not deliver anything.
        var nominal = Snapshot()
        nominal.sampled = true
        c.process(nominal, prefs: off, now: t0)
        c.process(hotSnapshot(), prefs: off, now: t0 + 2)
        c.process(criticalSnapshot(), prefs: off, now: t0 + 4)
        XCTAssertTrue(fake.delivered.isEmpty)
    }

    func testStateBeforeSwitchOnIsNotAnnouncedButNewRiseIs() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        // The Mac is already hot while the switch is off.
        c.process(hotSnapshot(), prefs: prefs(notify: false), now: t0)
        let on = prefs(notify: true)
        c.process(hotSnapshot(), prefs: on, now: t0 + 60)
        XCTAssertTrue(fake.delivered.isEmpty)
        // A new rise after enabling (Serious → Critical) is delivered.
        c.process(criticalSnapshot(), prefs: on, now: t0 + 120)
        XCTAssertEqual(fake.delivered.map(\.title), ["Thermal state: Critical"])
    }

    func testRiseAfterSwitchOffAndOnIsDeliveredDespiteEarlierState() {
        let fake = FakeNotifier()
        let c = AlertCoordinator(notifier: fake)
        let on = prefs(notify: true)
        c.process(hotSnapshot(), prefs: on, now: t0)
        XCTAssertEqual(fake.delivered.count, 2)
        // Switch off; the Mac cools down meanwhile.
        var nominal = Snapshot()
        nominal.sampled = true
        c.process(nominal, prefs: prefs(notify: false), now: t0 + 30)
        // Switch on again, the Mac heats up again after 11 minutes: delivered.
        c.process(hotSnapshot(), prefs: on, now: t0 + 700)
        XCTAssertEqual(fake.delivered.count, 4)
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
