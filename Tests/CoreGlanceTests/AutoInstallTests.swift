import XCTest
@testable import CoreGlance

/// coreglance#101: automatic installation after a check, and the reliable restart.
final class AutoInstallLogicTests: XCTestCase {
    private func release(_ v: String) -> ReleaseInfo {
        let u = URL(string: "https://github.com/a/b/CoreGlance.zip")!
        return ReleaseInfo(version: v, downloadURL: u, pageURL: u, checksumURL: u)
    }

    func testShouldInstallNowTable() {
        // (autoInstall, canInstall, available, failedVersion) -> expected
        let rows: [(Bool, Bool, ReleaseInfo?, String?, Bool)] = [
            (true, true, release("0.3.0"), nil, true),
            (false, true, release("0.3.0"), nil, false),       // switched off: never on its own
            (true, false, release("0.3.0"), nil, false),       // cannot replace itself
            (true, true, nil, nil, false),                     // nothing newer
            (true, true, release("0.3.0"), "0.3.0", false),    // this version already failed in this session
            (true, true, release("0.3.1"), "0.3.0", true),     // a newer version than the failed one is tried
        ]
        for (i, row) in rows.enumerated() {
            XCTAssertEqual(UpdateLogic.shouldInstallNow(autoInstall: row.0, canInstall: row.1, available: row.2, failedVersion: row.3),
                           row.4, "row \(i)")
        }
    }

    func testAutoInstallOptionNeedsChecksAndWritableApp() {
        XCTAssertEqual(UpdateLogic.autoInstallBlocker(autoUpdate: true, canReplaceSelf: true), nil)
        XCTAssertEqual(UpdateLogic.autoInstallBlocker(autoUpdate: false, canReplaceSelf: true),
                       "Turn on “Check for updates automatically” first.")
        XCTAssertEqual(UpdateLogic.autoInstallBlocker(autoUpdate: true, canReplaceSelf: false),
                       "CoreGlance is not in a writable folder, so it cannot replace itself.")
        XCTAssertNotNil(UpdateLogic.autoInstallBlocker(autoUpdate: false, canReplaceSelf: false))
    }

    func testRestartScriptWaitsForPidWithLimitInsteadOfFixedSleep() {
        let app = URL(fileURLWithPath: "/Applications/CoreGlance.app")
        let args = Updater.restartArguments(app: app, pid: 4242, timeout: 15)
        XCTAssertEqual(args.first, "-c")
        XCTAssertTrue(args[1].contains("kill -0"))
        XCTAssertFalse(args[1].contains("sleep 1;"), "no fixed one-second sleep")
        XCTAssertTrue(args[1].contains("open"))
        XCTAssertEqual(Array(args.dropFirst(3)), ["4242", "/Applications/CoreGlance.app", "15"])
    }

    func testRestartScriptReallyWaitsForPidToExit() throws {
        // A real child that lives ~0.5 s: the script must start "open" only after it is gone (here: touch a marker).
        let marker = FileManager.default.temporaryDirectory.appendingPathComponent("cg-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sleep")
        child.arguments = ["1"]
        try child.run()
        let args = Updater.restartArguments(app: marker, pid: child.processIdentifier, timeout: 15, opener: "/usr/bin/touch")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = args
        let start = Date()
        try p.run()
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path), "still waiting while the old instance lives")
        p.waitUntilExit()
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
        XCTAssertGreaterThan(Date().timeIntervalSince(start), 0.6)
        child.waitUntilExit()
    }
}

private struct StubNetwork: UpdateNetwork {
    let json: Data
    func latestReleaseJSON() async throws -> Data { json }
}

private final class CountingDownloader: UpdateDownloader {
    var files: [URL: Data] = [:]
    var calls = 0
    func download(_ url: URL, to file: URL) async throws {
        calls += 1
        guard let data = files[url] else { throw URLError(.fileDoesNotExist) }
        try data.write(to: file)
    }
}

@MainActor
final class UpdaterAutoInstallTests: XCTestCase {
    private let base = "https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/"
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite = ""

    override func setUpWithError() throws {
        suite = "coreglance.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("cg-auto-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: folder)
    }

    private var releaseJSON: Data {
        Data("""
        {"tag_name":"v0.3.0","draft":false,"prerelease":false,
         "html_url":"https://github.com/TheMartas29/CoreGlance/releases/tag/v0.3.0",
         "assets":[{"name":"CoreGlance.zip","browser_download_url":"\(base)CoreGlance.zip"},
                   {"name":"CoreGlance.zip.sha256","browser_download_url":"\(base)CoreGlance.zip.sha256"}]}
        """.utf8)
    }

    /// Real zip of a fake 0.3.0 app (ditto, like the release job) with a matching checksum file.
    private func goodDownloader() throws -> CountingDownloader {
        let src = folder.appendingPathComponent("src/CoreGlance.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: src, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "io.github.coreglance", "CFBundleShortVersionString": "0.3.0"]
        try (plist as NSDictionary).write(to: src.appendingPathComponent("Info.plist"))
        let zip = folder.appendingPathComponent("made.zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", folder.appendingPathComponent("src/CoreGlance.app").path, zip.path]
        try p.run(); p.waitUntilExit()
        let d = CountingDownloader()
        d.files[URL(string: base + "CoreGlance.zip")!] = try Data(contentsOf: zip)
        d.files[URL(string: base + "CoreGlance.zip.sha256")!] = Data("\(try UpdateLogic.sha256Hex(of: zip))  CoreGlance.zip\n".utf8)
        return d
    }

    private func installedApp() throws -> URL {
        let app = folder.appendingPathComponent("Apps/CoreGlance.app", isDirectory: true)
        let contents = app.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": "io.github.coreglance", "CFBundleShortVersionString": "0.2.0"]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        return app
    }

    func testPreferenceDefaultsToOffAndPersists() {
        let first = Preferences(defaults: defaults)
        XCTAssertFalse(first.autoInstall)
        first.autoInstall = true
        XCTAssertTrue(Preferences(defaults: defaults).autoInstall)
        first.autoInstall = false
        XCTAssertFalse(Preferences(defaults: defaults).autoInstall)
    }

    func testTickInstallsOnceWhenOnAndRelaunchesWithBusyState() async throws {
        let prefs = Preferences(defaults: defaults)
        prefs.autoInstall = true
        let downloader = try goodDownloader()
        let app = try installedApp()
        var relaunches = 0
        var stateAtRelaunch: Updater.InstallState?
        var updater: Updater!
        updater = Updater(prefs: prefs, network: StubNetwork(json: releaseJSON), currentVersion: "0.2.0",
                          downloader: downloader, appURL: app, bundleID: "io.github.coreglance",
                          relaunch: { _ in relaunches += 1; stateAtRelaunch = updater.installState })
        await updater.tick()
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(stateAtRelaunch, .installing, "button must stay disabled until the process exits")
        XCTAssertEqual(downloader.calls, 2)   // zip + checksum, once
    }

    func testFailedVersionIsNotRetriedInSessionAndMessageStays() async throws {
        let prefs = Preferences(defaults: defaults)
        prefs.autoInstall = true
        let downloader = CountingDownloader()      // no files: every download fails
        var relaunches = 0
        let updater = Updater(prefs: prefs, network: StubNetwork(json: releaseJSON), currentVersion: "0.2.0",
                              downloader: downloader, appURL: try installedApp(), bundleID: "io.github.coreglance",
                              relaunch: { _ in relaunches += 1 })
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        await updater.tick(now: t0)
        XCTAssertEqual(downloader.calls, 1)
        XCTAssertEqual(updater.installState, .failed(UpdateInstallError.downloadFailed.message))
        await updater.tick(now: t0.addingTimeInterval(25 * 3600))   // next due check finds the same version
        XCTAssertEqual(downloader.calls, 1, "same version is not retried automatically")
        XCTAssertEqual(updater.installState, .failed(UpdateInstallError.downloadFailed.message))
        XCTAssertEqual(relaunches, 0)
    }

    func testSwitchedOffNeverInstallsButManualButtonStillWorks() async throws {
        let prefs = Preferences(defaults: defaults)
        XCTAssertFalse(prefs.autoInstall)
        let downloader = try goodDownloader()
        var relaunches = 0
        let updater = Updater(prefs: prefs, network: StubNetwork(json: releaseJSON), currentVersion: "0.2.0",
                              downloader: downloader, appURL: try installedApp(), bundleID: "io.github.coreglance",
                              relaunch: { _ in relaunches += 1 })
        await updater.tick()
        XCTAssertEqual(downloader.calls, 0)
        XCTAssertEqual(relaunches, 0)
        XCTAssertEqual(updater.availableUpdate?.version, "0.3.0")
        await updater.installAvailable()
        XCTAssertEqual(relaunches, 1)
        XCTAssertEqual(downloader.calls, 2)
    }

    func testCheckSwitchedOffMakesNoRequestEvenWithAutoInstall() async throws {
        let prefs = Preferences(defaults: defaults)
        prefs.autoInstall = true
        prefs.autoUpdate = false
        let downloader = CountingDownloader()
        let updater = Updater(prefs: prefs, network: StubNetwork(json: releaseJSON), currentVersion: "0.2.0",
                              downloader: downloader, appURL: try installedApp(), bundleID: "io.github.coreglance", relaunch: { _ in })
        await updater.tick()
        XCTAssertNil(updater.availableUpdate)
        XCTAssertEqual(downloader.calls, 0)
    }
}
