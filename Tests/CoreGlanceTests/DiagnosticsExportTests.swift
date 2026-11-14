import XCTest
@testable import CoreGlance

final class DiagnosticsExportTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("coreglance-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Název souboru (ticket: CoreGlance-diagnostics-<model>-<datum>.txt)

    func testFileNameForRealModel() {
        let name = DiagnosticsExport.suggestedFileName(model: "Mac16,1", date: date(2026, 11, 14, 12, 0), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "CoreGlance-diagnostics-Mac16-1-2026-11-14.txt")
    }

    func testFileNameModelWithSpacesAndSlashes() {
        let name = DiagnosticsExport.suggestedFileName(model: "MacBook Pro / 14\" M5", date: date(2026, 1, 5, 12, 0), timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "CoreGlance-diagnostics-MacBook-Pro-14-M5-2026-01-05.txt")
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains(" "))
    }

    func testFileNameEmptyOrMissingModelFallsBackToMac() {
        let d = date(2026, 11, 14, 12, 0), utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(DiagnosticsExport.suggestedFileName(model: nil, date: d, timeZone: utc), "CoreGlance-diagnostics-Mac-2026-11-14.txt")
        XCTAssertEqual(DiagnosticsExport.suggestedFileName(model: " // ", date: d, timeZone: utc), "CoreGlance-diagnostics-Mac-2026-11-14.txt")
        XCTAssertEqual(DiagnosticsExport.sanitizedModel("../../etc"), "etc")
    }

    func testFileNameUsesLocalDay() {
        // 23:30 UTC 14. 11. je v Praze (UTC+1) už 15. 11.
        let d = date(2026, 11, 14, 23, 30)
        XCTAssertEqual(DiagnosticsExport.suggestedFileName(model: "Mac16,1", date: d, timeZone: TimeZone(identifier: "Europe/Prague")!),
                       "CoreGlance-diagnostics-Mac16-1-2026-11-15.txt")
    }

    // MARK: Zápis

    func testWriteStoresExactTextIncludingDiacritics() throws {
        let url = dir.appendingPathComponent("out.txt")
        let text = "CoreGlance diagnostics\nchip: Apple M5  teplota: 45 °C – čidlo žluťoučké"
        try DiagnosticsExport.write(text, to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
    }

    func testWriteReplacesExistingFileAndLeavesNoTemporaryFiles() throws {
        let url = dir.appendingPathComponent("out.txt")
        try DiagnosticsExport.write("old old old old", to: url)
        try DiagnosticsExport.write("new", to: url)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "new")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["out.txt"])
    }

    func testWriteToMissingFolderThrowsReadableError() {
        let url = dir.appendingPathComponent("neexistuje/out.txt")
        XCTAssertThrowsError(try DiagnosticsExport.write("x", to: url)) { error in
            let message = error.localizedDescription
            XCTAssertTrue(message.hasPrefix("Couldn't save the diagnostics: "), message)
            XCTAssertTrue(message.count > "Couldn't save the diagnostics: ".count, message)
        }
    }

    func testWriteToReadOnlyFolderThrowsAndKeepsNothing() throws {
        let ro = dir.appendingPathComponent("ro")
        try FileManager.default.createDirectory(at: ro, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o555])
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ro.path) }
        let target = ro.appendingPathComponent("out.txt")
        if FileManager.default.isWritableFile(atPath: ro.path) {
            // Spuštěno jako root: oprávnění se neuplatní, zápis tedy musí projít (explicitní assert, ne tiché přeskočení).
            XCTAssertEqual(geteuid(), 0, "složka 0o555 je zapisovatelná i pro neprivilegovaného uživatele")
            try DiagnosticsExport.write("x", to: target)
            XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "x")
            return
        }
        XCTAssertThrowsError(try DiagnosticsExport.write("x", to: target)) { error in
            XCTAssertTrue(error is DiagnosticsExportError)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: ro.path), [])
    }

    /// Nezapisovatelná cesta bez ohledu na root: rodič je obyčejný soubor (ENOTDIR).
    func testWriteWithFileAsParentThrowsReadableErrorEvenAsRoot() throws {
        let parent = dir.appendingPathComponent("soubor.txt")
        try Data("x".utf8).write(to: parent)
        XCTAssertThrowsError(try DiagnosticsExport.write("y", to: parent.appendingPathComponent("out.txt"))) { error in
            XCTAssertTrue(error is DiagnosticsExportError)
            XCTAssertTrue(error.localizedDescription.hasPrefix("Couldn't save the diagnostics: "))
        }
        XCTAssertEqual(try String(contentsOf: parent, encoding: .utf8), "x")
    }

    // MARK: Přechody stavu (čistá logika)

    func testTransitionsHappyPathToSaved() {
        var s = DiagnosticsExportState.idle
        s = s.next(.panelOpened); XCTAssertEqual(s, .choosingFile)
        s = s.next(.fileChosen); XCTAssertEqual(s, .generating)
        s = s.next(.finished(.success("a.txt"))); XCTAssertEqual(s, .saved(fileName: "a.txt"))
        XCTAssertEqual(s.next(.timeout), .idle)
    }

    func testTransitionsFailureAndCancel() {
        let err = DiagnosticsExportError(reason: "Disk full")
        let failed = DiagnosticsExportState.generating.next(.finished(.failure(err)))
        XCTAssertEqual(failed, .failed(message: "Couldn't save the diagnostics: Disk full"))
        XCTAssertEqual(failed.next(.timeout), .idle)
        XCTAssertEqual(DiagnosticsExportState.choosingFile.next(.panelCancelled), .idle)
    }

    func testTransitionsIgnoreEventsThatMakeNoSense() {
        XCTAssertEqual(DiagnosticsExportState.generating.next(.panelOpened), .generating)  // busy
        XCTAssertEqual(DiagnosticsExportState.choosingFile.next(.timeout), .choosingFile)  // zpožděný reset
        XCTAssertEqual(DiagnosticsExportState.idle.next(.finished(.success("a.txt"))), .idle)
        XCTAssertEqual(DiagnosticsExportState.saved(fileName: "a.txt").next(.panelOpened), .choosingFile)
    }

    // MARK: Exporter: okno s výsledkem a návrat do .idle

    @MainActor
    private final class MockPresenter: DiagnosticsResultPresenting {
        var calls: [(title: String, text: String, isFailure: Bool)] = []
        func present(title: String, text: String, isFailure: Bool) { calls.append((title, text, isFailure)) }
    }

    @MainActor
    private func makeExporter() -> (DiagnosticsExporter, MockPresenter, () -> [(TimeInterval, @MainActor () -> Void)]) {
        let presenter = MockPresenter()
        var pending: [(TimeInterval, @MainActor () -> Void)] = []
        let exporter = DiagnosticsExporter(presenter: presenter, schedule: { delay, work in pending.append((delay, work)) })
        return (exporter, presenter, { pending })
    }

    @MainActor
    func testSuccessPresentsAlertWithFileName() {
        let (exporter, presenter, _) = makeExporter()
        exporter.apply(.panelOpened); exporter.apply(.fileChosen)
        XCTAssertTrue(presenter.calls.isEmpty, "okno až po dokončení zápisu")
        exporter.apply(.finished(.success("CoreGlance-diagnostics-Mac16-1-2026-11-14.txt")))
        XCTAssertEqual(presenter.calls.count, 1)
        XCTAssertEqual(presenter.calls.first?.text, "CoreGlance-diagnostics-Mac16-1-2026-11-14.txt")
        XCTAssertEqual(presenter.calls.first?.isFailure, false)
    }

    @MainActor
    func testFailurePresentsAlertWithReadableReason() {
        let (exporter, presenter, _) = makeExporter()
        exporter.apply(.panelOpened); exporter.apply(.fileChosen)
        exporter.apply(.finished(.failure(DiagnosticsExportError(reason: "The folder is read-only"))))
        XCTAssertEqual(presenter.calls.count, 1)
        XCTAssertEqual(presenter.calls.first?.text, "Couldn't save the diagnostics: The folder is read-only")
        XCTAssertEqual(presenter.calls.first?.isFailure, true)
        XCTAssertFalse(presenter.calls.first?.text.isEmpty ?? true)
    }

    @MainActor
    func testCancelPresentsNothingAndSchedulesNothing() {
        let (exporter, presenter, pending) = makeExporter()
        exporter.apply(.panelOpened); exporter.apply(.panelCancelled)
        XCTAssertEqual(exporter.state, .idle)
        XCTAssertTrue(presenter.calls.isEmpty)
        XCTAssertTrue(pending().isEmpty)
    }

    @MainActor
    func testResultReturnsToIdleAfterTenSeconds() throws {
        let (exporter, _, pending) = makeExporter()
        exporter.apply(.panelOpened); exporter.apply(.fileChosen)
        exporter.apply(.finished(.success("a.txt")))
        XCTAssertEqual(exporter.state.message, "Saved a.txt")
        let timer = try XCTUnwrap(pending().first)
        XCTAssertEqual(timer.0, 10)
        timer.1()
        XCTAssertEqual(exporter.state, .idle)
        XCTAssertNil(exporter.state.message)
    }

    @MainActor
    func testStaleTimerDoesNotClearNewerResult() throws {
        let (exporter, _, pending) = makeExporter()
        exporter.apply(.panelOpened); exporter.apply(.fileChosen); exporter.apply(.finished(.success("a.txt")))
        exporter.apply(.panelOpened); exporter.apply(.fileChosen); exporter.apply(.finished(.success("b.txt")))
        XCTAssertEqual(pending().count, 2)
        pending()[0].1()  // starý časovač z prvního ukládání
        XCTAssertEqual(exporter.state, .saved(fileName: "b.txt"))
        pending()[1].1()
        XCTAssertEqual(exporter.state, .idle)
    }

    // MARK: Stav tlačítka

    func testBusyOnlyWhilePanelOrGeneration() {
        XCTAssertFalse(DiagnosticsExportState.idle.isBusy)
        XCTAssertTrue(DiagnosticsExportState.choosingFile.isBusy)
        XCTAssertTrue(DiagnosticsExportState.generating.isBusy)
        XCTAssertFalse(DiagnosticsExportState.saved(fileName: "a.txt").isBusy)
        XCTAssertFalse(DiagnosticsExportState.failed(message: "x").isBusy)
    }

    func testMessagesAndFailureFlag() {
        XCTAssertNil(DiagnosticsExportState.idle.message)
        XCTAssertNil(DiagnosticsExportState.generating.message)
        XCTAssertEqual(DiagnosticsExportState.saved(fileName: "a.txt").message, "Saved a.txt")
        XCTAssertEqual(DiagnosticsExportState.failed(message: "Disk full").message, "Disk full")
        XCTAssertTrue(DiagnosticsExportState.failed(message: "x").isFailure)
        XCTAssertFalse(DiagnosticsExportState.saved(fileName: "a.txt").isFailure)
    }

    // MARK: Soukromí (ticket: žádné jméno uživatele, název počítače ani domovská složka)

    func testDiagnosticsContainNoUserNameHostNameOrHomePath() {
        let text = Monitor().diagnostics()
        XCTAssertTrue(text.hasPrefix("CoreGlance diagnostics"))
        let home = NSHomeDirectory()
        let host = ProcessInfo.processInfo.hostName
        let shortHost = host.split(separator: ".").first.map(String.init) ?? host
        XCTAssertFalse(text.contains(home), "diagnostics leak home folder '\(home)'")
        // Jména hledáme jako celá slova: uživatel „client“ jinak "najde" IOReport kanál `client_reads`
        // (skutečný výskyt na stroji, kde test vznikl). Velmi krátká jména by se našla náhodou i tak.
        for secret in [NSUserName(), NSFullUserName(), host, shortHost] where secret.count >= 3 {
            let pattern = "(?<![A-Za-z0-9_])" + NSRegularExpression.escapedPattern(for: secret) + "(?![A-Za-z0-9_])"
            XCTAssertNil(text.range(of: pattern, options: .regularExpression), "diagnostics leak '\(secret)'")
        }
    }

    func testWordMatchHelperDoesNotFlagSubstrings() {
        // Hlídá samotný test soukromí: bez hranic slov by padal na „client_reads“.
        let pattern = "(?<![A-Za-z0-9_])client(?![A-Za-z0-9_])"
        XCTAssertNil("name=\"client_reads\" subgroup=\"clients (used)\"".range(of: pattern, options: .regularExpression))
        XCTAssertNotNil("path /Users/client/x".range(of: pattern, options: .regularExpression))
    }
}
