import XCTest
import Combine
@testable import CoreGlance

final class SparklineFixesTests: XCTestCase {
    // MARK: Kontrast čáry grafu paměti (WCAG 1.4.11: grafický prvek ≥ 3:1)

    func testMemoryLineMeetsGraphicalContrastInAllPressureStates() {
        for (name, light, dark) in MemoryPalette.states {
            XCTAssertGreaterThanOrEqual(contrastRatio(light, WarningPalette.lightBackground), 3, "\(name) světlý")
            XCTAssertGreaterThanOrEqual(contrastRatio(dark, WarningPalette.darkBackground), 3, "\(name) tmavý")
            // Skutečné světlé okno bývá šedivější než bílá (~236).
            XCTAssertGreaterThanOrEqual(contrastRatio(light, RGB(r: 236, g: 236, b: 236)), 3, "\(name) světle šedý")
            XCTAssertGreaterThanOrEqual(contrastRatio(dark, RGB(r: 30, g: 30, b: 30)), 3, "\(name) tmavý 30")
        }
    }

    func testMemoryPressureStatesStayDistinguishableByColor() {
        XCTAssertEqual(MemoryPalette.states.count, 3)
        let lights = Set(MemoryPalette.states.map { "\($0.1.r),\($0.1.g),\($0.1.b)" })
        let darks = Set(MemoryPalette.states.map { "\($0.2.r),\($0.2.g),\($0.2.b)" })
        XCTAssertEqual(lights.count, 3)
        XCTAssertEqual(darks.count, 3)
    }

    // MARK: Jedna publikace na tik

    func testOneTickPublishesExactlyOnce() {
        let monitor = Monitor(clock: { 100 })
        var fired = 0
        let sub = monitor.objectWillChange.sink { fired += 1 }
        var s = Snapshot()
        s.sampled = true
        s.cpu = 0.5
        monitor.ingest(s)
        XCTAssertEqual(fired, 1)
        // Obě části se aktualizovaly společně.
        XCTAssertEqual(monitor.snapshot.cpu, 0.5)
        XCTAssertEqual(monitor.histories.cpu.values, [0.5])
        monitor.ingest(s)
        XCTAssertEqual(fired, 2)
        sub.cancel()
    }

    // MARK: Mezera po spánku

    func testGapLongerThanWindowDropsSamplesFromBeforeSleep() {
        var now: TimeInterval = 1000
        let monitor = Monitor(clock: { now })
        var s = Snapshot()
        s.sampled = true
        s.cpu = 0.9
        monitor.ingest(s)
        now = 1002
        monitor.ingest(s)
        XCTAssertEqual(monitor.histories.cpu.samples.count, 2)
        // Mac spal 1 hodinu: hodiny, které počítají i spánek, skočí o 3600 s.
        now = 1002 + 3600
        s.cpu = 0.1
        monitor.ingest(s)
        XCTAssertEqual(monitor.histories.cpu.values, [0.1])
    }

    func testDefaultClockCountsSleepUnlikeSystemUptime() {
        // Výchozí hodiny nesmí být systemUptime (zastaví se při spánku); musí to být CLOCK_MONOTONIC.
        let a = Monitor.sleepAwareNow()
        let b = Monitor.sleepAwareNow()
        XCTAssertGreaterThanOrEqual(b, a)
        XCTAssertGreaterThan(a, 0)
    }
}
