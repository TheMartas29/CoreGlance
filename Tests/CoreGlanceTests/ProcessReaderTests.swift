import XCTest
@testable import CoreGlance

/// Top processes: pure CPU % / ranking logic on fixture data (hand-computed), the libproc source,
/// and the Monitor / Preferences / privacy wiring.
final class ProcessReaderTests: XCTestCase {
    private func s(_ pid: Int32, _ name: String, _ seconds: Double) -> ProcessSample {
        ProcessSample(pid: pid, name: name, cpuNanos: UInt64(seconds * 1e9))
    }

    private func base(_ samples: [ProcessSample]) -> [Int32: ProcessSample] {
        Dictionary(uniqueKeysWithValues: samples.map { ($0.pid, $0) })
    }

    // MARK: usages

    func testUsageIsCPUTimeDeltaOverElapsedTime() {
        // 1.0 s -> 1.5 s of CPU time = 0.5 s in 2 s = 25 % of one core
        let r = ProcessReader.usages(previous: base([s(10, "Safari", 1.0)]), current: [s(10, "Safari", 1.5)], dt: 2)
        XCTAssertEqual(r.count, 1)
        XCTAssertEqual(r[0].cpu, 25, accuracy: 0.001)
        XCTAssertEqual(r[0].name, "Safari")
    }

    func testMultiThreadedProcessCanExceedOneHundredPercent() {
        // 3 s of CPU time in 1 s = 300 % (three full cores, as Activity Monitor shows)
        let r = ProcessReader.usages(previous: base([s(1, "ffmpeg", 5)]), current: [s(1, "ffmpeg", 8)], dt: 1)
        XCTAssertEqual(r[0].cpu, 300, accuracy: 0.001)
    }

    func testNewAndVanishedPidsAreIgnored() {
        let prev = base([s(1, "gone", 1), s(2, "stay", 1)])
        let r = ProcessReader.usages(previous: prev, current: [s(2, "stay", 2), s(3, "fresh", 9)], dt: 1)
        XCTAssertEqual(r.map(\.name), ["stay"])
        XCTAssertEqual(r[0].cpu, 100, accuracy: 0.001)
    }

    func testReusedPidWithDifferentNameIsIgnored() {
        let r = ProcessReader.usages(previous: base([s(5, "old", 1)]), current: [s(5, "new", 3)], dt: 1)
        XCTAssertTrue(r.isEmpty)
    }

    func testCounterGoingDownIsIgnoredNotWrapped() {
        // a counter that went from 10 s to 2 s must not become a huge unsigned delta
        let r = ProcessReader.usages(previous: base([s(5, "x", 10)]), current: [s(5, "x", 2)], dt: 1)
        XCTAssertTrue(r.isEmpty)
        let nearMax = ProcessSample(pid: 6, name: "y", cpuNanos: UInt64.max)
        let wrapped = ProcessSample(pid: 6, name: "y", cpuNanos: 5)
        XCTAssertTrue(ProcessReader.usages(previous: [6: nearMax], current: [wrapped], dt: 1).isEmpty)
    }

    func testZeroOrNegativeDtGivesNothing() {
        let prev = base([s(1, "a", 1)])
        XCTAssertTrue(ProcessReader.usages(previous: prev, current: [s(1, "a", 2)], dt: 0).isEmpty)
        XCTAssertTrue(ProcessReader.usages(previous: prev, current: [s(1, "a", 2)], dt: -3).isEmpty)
    }

    func testEmptyNameIsSkipped() {
        let r = ProcessReader.usages(previous: base([s(1, "", 1)]), current: [s(1, "", 2)], dt: 1)
        XCTAssertTrue(r.isEmpty)
    }

    // MARK: top

    private func u(_ pid: Int32, _ name: String, _ cpu: Double) -> ProcessUsage { ProcessUsage(pid: pid, name: name, cpu: cpu) }

    func testTopTakesFiveHighestInOrder() {
        let all = [u(1, "a", 10), u(2, "b", 70), u(3, "c", 30), u(4, "d", 90), u(5, "e", 50), u(6, "f", 20), u(7, "g", 5)]
        XCTAssertEqual(ProcessReader.top(all, count: 5).map(\.name), ["d", "b", "e", "c", "f"])
    }

    func testTopTiesAreOrderedByNameThenPid() {
        let all = [u(9, "zeta", 40), u(8, "alpha", 40), u(7, "alpha", 40), u(1, "mid", 40)]
        XCTAssertEqual(ProcessReader.top(all, count: 5).map(\.pid), [7, 8, 1, 9])
        XCTAssertEqual(ProcessReader.top(all.reversed(), count: 5).map(\.pid), [7, 8, 1, 9])
    }

    func testTopReturnsFewerWhenFewerProcessesAndDropsIdle() {
        XCTAssertEqual(ProcessReader.top([u(1, "a", 5), u(2, "idle", 0)], count: 5).map(\.name), ["a"])
        XCTAssertTrue(ProcessReader.top([], count: 5).isEmpty)
        XCTAssertTrue(ProcessReader.top([u(1, "a", 5)], count: 0).isEmpty)
    }

    // MARK: rows

    func testRowsFormatNameAndPercent() {
        let rows = ProcessReader.rows([u(1, "Xcode", 12.34), u(2, "Café – prohlížeč", 250)])
        XCTAssertEqual(rows.map(\.name), ["Xcode", "Café – prohlížeč"])
        XCTAssertEqual(rows.map(\.value), ["12.3%", "250.0%"])
    }

    func testRowsShortenLongNamesAndEmptyListGivesNoRows() {
        let long = String(repeating: "a", count: 40)
        XCTAssertEqual(ProcessReader.rows([u(1, long, 1)])[0].name, String(repeating: "a", count: 23) + "…")
        XCTAssertTrue(ProcessReader.rows([]).isEmpty)
    }

    // MARK: ticks

    func testNanosecondsUsesTimebaseRatio() {
        // Apple Silicon timebase 125/3: 3 ticks = 125 ns, 24 ticks = 1000 ns
        XCTAssertEqual(ProcessReader.nanoseconds(ticks: 3, numer: 125, denom: 3), 125)
        XCTAssertEqual(ProcessReader.nanoseconds(ticks: 24, numer: 125, denom: 3), 1000)
        XCTAssertEqual(ProcessReader.nanoseconds(ticks: 77, numer: 1, denom: 1), 77)
        XCTAssertEqual(ProcessReader.nanoseconds(ticks: 77, numer: 1, denom: 0), 77)  // broken timebase: no crash
        _ = ProcessReader.nanoseconds(ticks: UInt64.max, numer: 125, denom: 3)  // huge value must not trap
    }

    // MARK: reader with injected source

    func testFirstSampleOnlyStoresBaselineThenReportsAndForgetsVanished() {
        var time = 100.0
        var procs = [s(1, "A", 0), s(2, "B", 0)]
        let reader = ProcessReader(count: 5, source: { procs }, clock: { time })
        XCTAssertTrue(reader.sample().isEmpty)  // baseline only

        time = 102
        procs = [s(1, "A", 1), s(2, "B", 0.2)]  // A: 1 s / 2 s = 50 %, B: 0.2 / 2 = 10 %
        let second = reader.sample()
        XCTAssertEqual(second.map(\.name), ["A", "B"])
        XCTAssertEqual(second[0].cpu, 50, accuracy: 0.001)
        XCTAssertEqual(second[1].cpu, 10, accuracy: 0.001)

        time = 104
        procs = [s(2, "B", 0.6)]  // A vanished; B: 0.4 / 2 = 20 %
        let third = reader.sample()
        XCTAssertEqual(third.map(\.name), ["B"])
        XCTAssertEqual(third[0].cpu, 20, accuracy: 0.001)
    }

    func testResetForgetsBaseline() {
        var time = 0.0
        var procs = [s(1, "A", 0)]
        let reader = ProcessReader(source: { procs }, clock: { time })
        _ = reader.sample()
        reader.reset()
        time = 1; procs = [s(1, "A", 1)]
        XCTAssertTrue(reader.sample().isEmpty)
    }

    // MARK: live libproc

    func testLiveSourceSeesOwnProcessWithoutRoot() {
        let live = ProcessReader.liveSource()
        let me = live.first { $0.pid == getpid() }
        XCTAssertNotNil(me)
        XCTAssertFalse(me?.name.isEmpty ?? true)
        XCTAssertTrue(live.allSatisfy { !$0.name.isEmpty && $0.pid > 0 })
    }

    func testLiveReaderSampleDoesNotCrash() {
        let reader = ProcessReader()
        XCTAssertTrue(reader.sample().isEmpty)
        _ = reader.sample()
    }

    // MARK: Monitor, Preferences, privacy

    /// Fixture processes whose CPU time grows by 1 s per call; the clock advances 2 s per call (= 50 % each).
    private final class Fixture {
        var calls = 0
        let names = ["SecretProjectBuilder", "PrivateMailClient"]
        func source() -> [ProcessSample] {
            calls += 1
            return names.enumerated().map { ProcessSample(pid: Int32($0.offset + 1), name: $0.element, cpuNanos: UInt64(calls) * 1_000_000_000) }
        }
        func clock() -> TimeInterval { Double(calls) * 2 }
    }

    func testMonitorFillsTopProcessesWhenEnabled() {
        let f = Fixture()
        let monitor = Monitor(processes: ProcessReader(source: f.source, clock: f.clock))
        _ = monitor.readNow()  // baseline
        let snap = monitor.readNow()
        XCTAssertEqual(snap.topProcesses.map(\.name), ["PrivateMailClient", "SecretProjectBuilder"])
        XCTAssertEqual(snap.topProcesses[0].cpu, 50, accuracy: 0.001)
    }

    func testMonitorDoesNotCallReaderWhenDisabled() {
        let f = Fixture()
        let monitor = Monitor(processes: ProcessReader(source: f.source, clock: f.clock))
        monitor.showTopProcesses = false
        _ = monitor.readNow()
        let snap = monitor.readNow()
        XCTAssertEqual(f.calls, 0)
        XCTAssertTrue(snap.topProcesses.isEmpty)
    }

    func testDiagnosticsNeverContainProcessNames() {
        let f = Fixture()
        let monitor = Monitor(processes: ProcessReader(source: f.source, clock: f.clock))
        let text = monitor.diagnostics()  // reads twice, so the fixture does produce usages
        XCTAssertGreaterThanOrEqual(f.calls, 2)
        XCTAssertFalse(monitor.readNow().topProcesses.isEmpty)
        for name in f.names { XCTAssertFalse(text.contains(name), "diagnostics leaked \(name)") }
        XCTAssertFalse(text.contains("topProcesses"))
    }

    func testPreferenceDefaultsOnAndRoundTrips() throws {
        let suite = "coreglance.tests.procs.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(Preferences(defaults: defaults).showTopProcesses)
        let p = Preferences(defaults: defaults)
        p.showTopProcesses = false
        XCTAssertFalse(Preferences(defaults: defaults).showTopProcesses)
        p.showTopProcesses = true
        XCTAssertTrue(Preferences(defaults: defaults).showTopProcesses)
    }
}
