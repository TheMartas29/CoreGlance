import XCTest
@testable import CoreGlance

final class UpdateLogicTests: XCTestCase {
    // Pairs written by hand from the ticket (coreglance#18).
    func testVersionComparison() {
        XCTAssertTrue(UpdateLogic.isNewer("0.2.3", than: "0.2.2"))
        XCTAssertTrue(UpdateLogic.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertTrue(UpdateLogic.isNewer("v1.0.0", than: "0.9.9"))
        XCTAssertFalse(UpdateLogic.isNewer("v0.3.0", than: "0.3.0"))
        XCTAssertFalse(UpdateLogic.isNewer("0.2.2", than: "0.2.2"))
        XCTAssertFalse(UpdateLogic.isNewer("0.2.1", than: "0.2.2"))
        XCTAssertFalse(UpdateLogic.isNewer("0.3", than: "0.3.0"))
    }

    func testUnparsableTagIsNoUpdate() {
        for bad in ["", "latest", "v", "1.2.3-beta", "1..2", "1.2.3.4", "-1.0.0", "١.٢.٣"] {
            XCTAssertFalse(UpdateLogic.isNewer(bad, than: "0.0.1"), bad)
        }
        XCTAssertFalse(UpdateLogic.isNewer("9.9.9", than: "dev"))
    }

    private func releaseJSON(tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false,
                             assets: String = #"[{"name":"CoreGlance.zip","browser_download_url":"https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip"}]"#) -> Data {
        Data("""
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/TheMartas29/CoreGlance/releases/tag/\(tag)",
         "body":"Opraveno: příliš žluťoučký kůň úpěl ďábelské ódy – 🌡️",
         "assets":\(assets)}
        """.utf8)
    }

    func testParsesReleaseWithCzechNotes() throws {
        let info = try XCTUnwrap(UpdateLogic.parseRelease(releaseJSON()))
        XCTAssertEqual(info.version, "0.3.0")
        XCTAssertEqual(info.downloadURL.absoluteString, "https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip")
        XCTAssertEqual(info.pageURL.absoluteString, "https://github.com/TheMartas29/CoreGlance/releases/tag/v0.3.0")
    }

    func testPicksAssetByExactName() throws {
        let assets = #"[{"name":"CoreGlance.zip.sha256","browser_download_url":"https://github.com/x/wrong1"},{"name":"CoreGlance.zip","browser_download_url":"https://github.com/x/right"}]"#
        XCTAssertEqual(UpdateLogic.parseRelease(releaseJSON(assets: assets))?.downloadURL.absoluteString, "https://github.com/x/right")
    }

    func testRejectsDraftPrereleaseMissingAssetAndBrokenJSON() {
        XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(draft: true)))
        XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(prerelease: true)))
        XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(assets: "[]")))
        XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(assets: #"[{"name":"Other.zip","browser_download_url":"https://github.com/x/y"}]"#)))
        XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(tag: "nightly")))
        XCTAssertNil(UpdateLogic.parseRelease(Data("{ not json".utf8)))
        XCTAssertNil(UpdateLogic.parseRelease(Data()))
        XCTAssertNil(UpdateLogic.parseRelease(Data(#"{"message":"API rate limit exceeded"}"#.utf8)))
    }

    func testRejectsForeignOrInsecureDownloadHost() {
        for url in ["https://evil.example.com/CoreGlance.zip", "http://github.com/CoreGlance.zip", "https://notgithub.com/CoreGlance.zip"] {
            let assets = #"[{"name":"CoreGlance.zip","browser_download_url":"\#(url)"}]"#
            XCTAssertNil(UpdateLogic.parseRelease(releaseJSON(assets: assets)), url)
        }
    }

    func testSchedule() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let h = 3600.0
        XCTAssertTrue(UpdateLogic.isCheckDue(enabled: true, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateLogic.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-23 * h), now: now))
        XCTAssertTrue(UpdateLogic.isCheckDue(enabled: true, lastCheck: now.addingTimeInterval(-24 * h), now: now))
        XCTAssertFalse(UpdateLogic.isCheckDue(enabled: false, lastCheck: nil, now: now))
        XCTAssertFalse(UpdateLogic.isCheckDue(enabled: false, lastCheck: now.addingTimeInterval(-48 * h), now: now))
    }

    func testAvailableUpdateOnlyWhileNewer() throws {
        let url = try XCTUnwrap(URL(string: "https://github.com/a/b"))
        let known = ReleaseInfo(version: "0.3.0", downloadURL: url, pageURL: url)
        XCTAssertEqual(UpdateLogic.availableUpdate(known: known, current: "0.2.2")?.version, "0.3.0")
        XCTAssertNil(UpdateLogic.availableUpdate(known: known, current: "0.3.0"))
        XCTAssertNil(UpdateLogic.availableUpdate(known: nil, current: "0.2.2"))
    }
}

final class UpdatePreferencesTests: XCTestCase {
    private func suite() throws -> (UserDefaults, String) {
        let name = "coreglance.tests.\(UUID().uuidString)"
        return (try XCTUnwrap(UserDefaults(suiteName: name)), name)
    }

    func testAutoUpdateDefaultsOnAndSurvivesRestart() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Preferences(defaults: defaults)
        XCTAssertTrue(first.autoUpdate)
        first.autoUpdate = false
        XCTAssertFalse(Preferences(defaults: defaults).autoUpdate)
        first.autoUpdate = true
        XCTAssertTrue(Preferences(defaults: defaults).autoUpdate)
    }

    func testKnownReleaseAndLastCheckPersist() throws {
        let (defaults, name) = try suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let url = try XCTUnwrap(URL(string: "https://github.com/a/b/c.zip"))
        let prefs = Preferences(defaults: defaults)
        XCTAssertNil(prefs.knownRelease)
        XCTAssertNil(prefs.lastUpdateCheck)
        prefs.knownRelease = ReleaseInfo(version: "0.3.0", downloadURL: url, pageURL: url)
        prefs.lastUpdateCheck = Date(timeIntervalSince1970: 100)
        let again = Preferences(defaults: defaults)
        XCTAssertEqual(again.knownRelease?.version, "0.3.0")
        XCTAssertEqual(again.lastUpdateCheck, Date(timeIntervalSince1970: 100))
        again.knownRelease = nil
        XCTAssertNil(Preferences(defaults: defaults).knownRelease)
    }
}

private final class FakeNetwork: UpdateNetwork {
    var json = Data()
    var zip: URL?
    var jsonCalls = 0
    var downloadCalls = 0
    func latestReleaseJSON() async throws -> Data { jsonCalls += 1; return json }
    func download(_ url: URL, to file: URL) async throws {
        downloadCalls += 1
        guard let zip else { throw URLError(.cannotConnectToHost) }
        try FileManager.default.copyItem(at: zip, to: file)
    }
}

/// Updater scheduling and the whole check → download → install path over fake network and a temp folder.
@MainActor
final class UpdaterTests: XCTestCase {
    private var root: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("coreglance-updater-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suiteName = "coreglance.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("apps").path)
        try? FileManager.default.removeItem(at: root)
    }

    private func release(version: String) -> Data {
        Data("""
        {"tag_name":"v\(version)","draft":false,"prerelease":false,"html_url":"https://github.com/TheMartas29/CoreGlance/releases/tag/v\(version)",
         "assets":[{"name":"CoreGlance.zip","browser_download_url":"https://github.com/TheMartas29/CoreGlance/releases/download/v\(version)/CoreGlance.zip"}]}
        """.utf8)
    }

    /// Builds `<root>/<dir>/CoreGlance.app` with the given Info.plist values and returns the app URL.
    private func makeApp(in dir: String, bundleID: String = "io.github.coreglance", version: String, marker: String) throws -> URL {
        let app = root.appendingPathComponent(dir).appendingPathComponent("CoreGlance.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        XCTAssertTrue(plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))
        try marker.write(to: contents.appendingPathComponent("marker.txt"), atomically: true, encoding: .utf8)
        return app
    }

    private func zip(_ app: URL, name: String = "CoreGlance.zip") throws -> URL {
        let out = root.appendingPathComponent(name)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", app.path, out.path]
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0)
        return out
    }

    private func marker(_ app: URL) -> String? {
        try? String(contentsOf: app.appendingPathComponent("Contents/marker.txt"), encoding: .utf8)
    }

    private func updater(_ prefs: Preferences, _ net: FakeNetwork, target: URL, current: String? = "0.2.2",
                         relaunched: @escaping (URL) -> Void = { _ in }) -> Updater {
        Updater(prefs: prefs, network: net, currentVersion: current, target: target, relaunch: relaunched)
    }

    func testSwitchedOffMakesNoRequestAndNoInstall() async throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let net = FakeNetwork()
        net.json = release(version: "0.3.0")
        net.zip = try zip(try makeApp(in: "new", version: "0.3.0", marker: "new"))
        let prefs = Preferences(defaults: defaults)
        prefs.autoUpdate = false
        await updater(prefs, net, target: target).tick()
        XCTAssertEqual(net.jsonCalls, 0)
        XCTAssertEqual(net.downloadCalls, 0)
        XCTAssertEqual(marker(target), "old")
    }

    func testChecksOnceAndThenAtMostEvery24Hours() async throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let net = FakeNetwork()
        net.json = release(version: "0.2.2")   // nothing newer
        let u = updater(Preferences(defaults: defaults), net, target: target)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        await u.tick(now: t0)
        await u.tick(now: t0.addingTimeInterval(3600))
        await u.tick(now: t0.addingTimeInterval(23 * 3600))
        XCTAssertEqual(net.jsonCalls, 1)
        await u.tick(now: t0.addingTimeInterval(24 * 3600))
        XCTAssertEqual(net.jsonCalls, 2)
    }

    func testInstallsNewReleaseAndRestarts() async throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let net = FakeNetwork()
        net.json = release(version: "0.3.0")
        net.zip = try zip(try makeApp(in: "new", version: "0.3.0", marker: "new"))
        var relaunched: URL?
        await updater(Preferences(defaults: defaults), net, target: target) { relaunched = $0 }.tick()
        XCTAssertEqual(marker(target), "new")
        XCTAssertEqual(relaunched, target)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path)
        XCTAssertEqual(leftovers, ["CoreGlance.app"])
    }

    func testNetworkErrorOrBadJSONLeavesAppAndDoesNotRecordCheck() async throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let net = FakeNetwork()
        net.json = Data("{ nope".utf8)
        let prefs = Preferences(defaults: defaults)
        await updater(prefs, net, target: target).tick()
        XCTAssertEqual(marker(target), "old")
        XCTAssertNil(prefs.knownRelease)
        // Valid release but the download fails: app untouched, update stays offered.
        net.json = release(version: "0.3.0")
        net.zip = nil
        prefs.lastUpdateCheck = nil
        await updater(prefs, net, target: target).tick()
        XCTAssertEqual(marker(target), "old")
        XCTAssertEqual(prefs.knownRelease?.version, "0.3.0")
    }

    func testUnwritableTargetOnlyOffersUpdate() async throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.deletingLastPathComponent().path)
        let net = FakeNetwork()
        net.json = release(version: "0.3.0")
        net.zip = try zip(try makeApp(in: "new", version: "0.3.0", marker: "new"))
        let prefs = Preferences(defaults: defaults)
        let u = updater(prefs, net, target: target)
        await u.tick()
        XCTAssertEqual(net.downloadCalls, 0)
        XCTAssertEqual(marker(target), "old")
        XCTAssertEqual(u.availableUpdate?.version, "0.3.0")
        XCTAssertEqual(u.availableUpdate?.pageURL.absoluteString, "https://github.com/TheMartas29/CoreGlance/releases/tag/v0.3.0")
        // Switched off later: the known update is still shown, with no further request.
        prefs.autoUpdate = false
        XCTAssertEqual(u.availableUpdate?.version, "0.3.0")
    }

    func testNoVersionMeansUpdaterIsInert() async throws {   // `swift run` binary without Info.plist
        let net = FakeNetwork()
        net.json = release(version: "0.3.0")
        let u = updater(Preferences(defaults: defaults), net, target: root.appendingPathComponent("CoreGlance"), current: nil)
        await u.tick()
        XCTAssertEqual(net.jsonCalls, 0)
        XCTAssertNil(u.availableUpdate)
    }

    // MARK: installer

    func testInstallerRejectsBadInputsAndKeepsOriginal() throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let work = root.appendingPathComponent("work")
        func attempt(_ zipFile: URL, _ current: String = "0.2.2") -> UpdateInstallError? {
            try? FileManager.default.removeItem(at: work)
            try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            do { try UpdateInstaller.install(zip: zipFile, into: target, currentVersion: current, workDir: work); return nil }
            catch { return error as? UpdateInstallError }
        }
        let corrupt = root.appendingPathComponent("corrupt.zip")
        try Data("this is not a zip".utf8).write(to: corrupt)
        XCTAssertEqual(attempt(corrupt), .unzipFailed)
        XCTAssertEqual(attempt(try zip(try makeApp(in: "other", bundleID: "com.example.other", version: "0.3.0", marker: "x"), name: "other.zip")), .wrongBundleID)
        XCTAssertEqual(attempt(try zip(try makeApp(in: "same", version: "0.2.2", marker: "x"), name: "same.zip")), .notNewer)
        XCTAssertEqual(attempt(try zip(try makeApp(in: "older", version: "0.1.0", marker: "x"), name: "older.zip")), .notNewer)
        XCTAssertEqual(marker(target), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path), ["CoreGlance.app"])
    }

    func testInstallerNeedsAnAppBundleAndWritableFolder() throws {
        let target = try makeApp(in: "apps", version: "0.2.2", marker: "old")
        let good = try zip(try makeApp(in: "new", version: "0.3.0", marker: "new"))
        let work = root.appendingPathComponent("work")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        XCTAssertThrowsError(try UpdateInstaller.install(zip: good, into: root.appendingPathComponent("CoreGlance"), currentVersion: "0.2.2", workDir: work)) {
            XCTAssertEqual($0 as? UpdateInstallError, .notAnApp)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: target.deletingLastPathComponent().path)
        XCTAssertThrowsError(try UpdateInstaller.install(zip: good, into: target, currentVersion: "0.2.2", workDir: work)) {
            XCTAssertEqual($0 as? UpdateInstallError, .notWritable)
        }
        XCTAssertEqual(marker(target), "old")
    }
}
