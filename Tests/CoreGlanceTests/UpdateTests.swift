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

    static func releaseJSON(tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false,
                            assets: String = #"[{"name":"CoreGlance.zip","browser_download_url":"https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip"}]"#) -> Data {
        Data("""
        {"tag_name":"\(tag)","draft":\(draft),"prerelease":\(prerelease),
         "html_url":"https://github.com/TheMartas29/CoreGlance/releases/tag/\(tag)",
         "body":"Opraveno: příliš žluťoučký kůň úpěl ďábelské ódy – 🌡️",
         "assets":\(assets)}
        """.utf8)
    }
    private func releaseJSON(tag: String = "v0.3.0", draft: Bool = false, prerelease: Bool = false, assets: String? = nil) -> Data {
        assets.map { Self.releaseJSON(tag: tag, draft: draft, prerelease: prerelease, assets: $0) }
            ?? Self.releaseJSON(tag: tag, draft: draft, prerelease: prerelease)
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
    var jsonCalls = 0
    var fail = false
    func latestReleaseJSON() async throws -> Data {
        jsonCalls += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return json
    }
}

/// Updater scheduling and "update available" state over a fake network (the only boundary).
@MainActor
final class UpdaterTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suiteName = "coreglance.tests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suiteName) }

    private func release(_ version: String) -> Data {
        UpdateLogicTests.releaseJSON(tag: "v\(version)")
    }

    private func updater(_ prefs: Preferences, _ net: FakeNetwork, current: String? = "0.2.2") -> Updater {
        Updater(prefs: prefs, network: net, currentVersion: current)
    }

    func testSwitchedOffMakesNoRequest() async {
        let net = FakeNetwork()
        net.json = release("0.3.0")
        let prefs = Preferences(defaults: defaults)
        prefs.autoUpdate = false
        let u = updater(prefs, net)
        await u.tick()
        XCTAssertEqual(net.jsonCalls, 0)
        XCTAssertNil(u.availableUpdate)
    }

    func testChecksOnceAndThenAtMostEvery24Hours() async {
        let net = FakeNetwork()
        net.json = release("0.2.2")   // nothing newer
        let u = updater(Preferences(defaults: defaults), net)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        await u.tick(now: t0)
        await u.tick(now: t0.addingTimeInterval(3600))
        await u.tick(now: t0.addingTimeInterval(23 * 3600))
        XCTAssertEqual(net.jsonCalls, 1)
        await u.tick(now: t0.addingTimeInterval(24 * 3600))
        XCTAssertEqual(net.jsonCalls, 2)
    }

    func testNewerReleaseIsOfferedWithLinkAndSurvivesSwitchingOff() async {
        let net = FakeNetwork()
        net.json = release("0.3.0")
        let prefs = Preferences(defaults: defaults)
        let u = updater(prefs, net)
        await u.tick()
        XCTAssertEqual(u.availableUpdate?.version, "0.3.0")
        XCTAssertEqual(u.availableUpdate?.pageURL.absoluteString, "https://github.com/TheMartas29/CoreGlance/releases/tag/v0.3.0")
        prefs.autoUpdate = false
        XCTAssertEqual(u.availableUpdate?.version, "0.3.0")
    }

    func testNetworkErrorAndBadJSONAreSilentAndRetried() async {
        let net = FakeNetwork()
        net.fail = true
        let prefs = Preferences(defaults: defaults)
        let u = updater(prefs, net)
        await u.tick()
        XCTAssertNil(u.availableUpdate)
        XCTAssertNil(prefs.lastUpdateCheck)          // a failed request does not count as a check
        net.fail = false
        net.json = Data("{ nope".utf8)
        await u.tick()
        XCTAssertNil(u.availableUpdate)
        XCTAssertEqual(net.jsonCalls, 2)             // retried after the failure, not after an answered request
    }

    func testNoVersionMeansUpdaterIsInert() async {   // `swift run` binary without Info.plist
        let net = FakeNetwork()
        net.json = release("0.3.0")
        let u = updater(Preferences(defaults: defaults), net, current: nil)
        await u.tick()
        XCTAssertEqual(net.jsonCalls, 0)
        XCTAssertNil(u.availableUpdate)
    }
}
