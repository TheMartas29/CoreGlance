import XCTest
@testable import CoreGlance

private let emptySHA = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" // SHA-256 of zero bytes (FIPS 180-4 test vector)
private let abcSHA = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"   // SHA-256 of "abc"

final class UpdateChecksumTests: XCTestCase {
    private func releaseWith(assets: String) -> ReleaseInfo? {
        UpdateLogic.parseRelease(UpdateLogicTests.releaseJSON(assets: assets))
    }
    private let zipAsset = #"{"name":"CoreGlance.zip","browser_download_url":"https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip"}"#

    func testChecksumAssetBecomesChecksumURL() {
        let sum = #"{"name":"CoreGlance.zip.sha256","browser_download_url":"https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip.sha256"}"#
        XCTAssertEqual(releaseWith(assets: "[\(zipAsset),\(sum)]")?.checksumURL?.lastPathComponent, "CoreGlance.zip.sha256")
    }

    func testNoChecksumAssetOrUntrustedHostMeansNoChecksum() {
        XCTAssertNil(releaseWith(assets: "[\(zipAsset)]")?.checksumURL)
        XCTAssertNotNil(releaseWith(assets: "[\(zipAsset)]"))
        let evil = #"{"name":"CoreGlance.zip.sha256","browser_download_url":"https://evil.example.com/CoreGlance.zip.sha256"}"#
        let info = releaseWith(assets: "[\(zipAsset),\(evil)]")
        XCTAssertNotNil(info)
        XCTAssertNil(info?.checksumURL)
    }

    func testParseChecksumAcceptsShasumLineWithOrWithoutName() {
        XCTAssertEqual(UpdateLogic.parseChecksum("\(emptySHA)  CoreGlance.zip\n"), emptySHA)
        XCTAssertEqual(UpdateLogic.parseChecksum(emptySHA), emptySHA)
        XCTAssertEqual(UpdateLogic.parseChecksum("\n\(emptySHA.uppercased()) *CoreGlance.zip"), emptySHA)
    }

    func testParseChecksumRejectsBadInput() {
        XCTAssertNil(UpdateLogic.parseChecksum(""))
        XCTAssertNil(UpdateLogic.parseChecksum("  \n "))
        XCTAssertNil(UpdateLogic.parseChecksum(String(emptySHA.dropLast())))        // 63 chars
        XCTAssertNil(UpdateLogic.parseChecksum(emptySHA + "0"))                      // 65 chars
        XCTAssertNil(UpdateLogic.parseChecksum(String(repeating: "g", count: 64)))   // not hex
        XCTAssertNil(UpdateLogic.parseChecksum("\(emptySHA)  Other.zip"))
        XCTAssertNil(UpdateLogic.parseChecksum("\(emptySHA) CoreGlance.zip extra"))
    }

    func testChecksumMatchesOnlyTheSameDigest() {
        XCTAssertTrue(UpdateLogic.checksumMatches("\(abcSHA)  CoreGlance.zip", digest: abcSHA))
        XCTAssertFalse(UpdateLogic.checksumMatches("\(emptySHA)  CoreGlance.zip", digest: abcSHA))
        XCTAssertFalse(UpdateLogic.checksumMatches("", digest: emptySHA))
        XCTAssertFalse(UpdateLogic.checksumMatches("short", digest: "short"))
    }

    func testSha256OfFileKnownVectors() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cg-sha-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let empty = dir.appendingPathComponent("empty"), abc = dir.appendingPathComponent("abc")
        try Data().write(to: empty)
        try Data("abc".utf8).write(to: abc)
        XCTAssertEqual(try UpdateLogic.sha256Hex(of: empty), emptySHA)
        XCTAssertEqual(try UpdateLogic.sha256Hex(of: abc), abcSHA)
    }

    func testChecksumURLPersists() throws {
        let name = "coreglance.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let url = try XCTUnwrap(URL(string: "https://github.com/a/b/c.zip"))
        let sum = try XCTUnwrap(URL(string: "https://github.com/a/b/c.zip.sha256"))
        Preferences(defaults: defaults).knownRelease = ReleaseInfo(version: "0.3.0", downloadURL: url, pageURL: url, checksumURL: sum)
        XCTAssertEqual(Preferences(defaults: defaults).knownRelease?.checksumURL, sum)
    }
}

/// Serves prepared files instead of the network.
private final class FakeDownloader: UpdateDownloader {
    var files: [URL: Data] = [:]
    func download(_ url: URL, to file: URL) async throws {
        guard let data = files[url] else { throw URLError(.fileDoesNotExist) }
        try data.write(to: file)
    }
}

final class UpdateInstallerTests: XCTestCase {
    private let zipURL = URL(string: "https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip")!
    private let sumURL = URL(string: "https://github.com/TheMartas29/CoreGlance/releases/download/v0.3.0/CoreGlance.zip.sha256")!
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("cg-inst-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root) }

    private func writeApp(at dir: URL, version: String, bundleID: String = "io.github.coreglance", marker: String = "new") throws {
        let contents = dir.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version]
        try (plist as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        try Data(marker.utf8).write(to: contents.appendingPathComponent("marker"))
    }

    /// Real zip made with ditto, like the release job does.
    private func makeZip(version: String = "0.3.0", bundleID: String = "io.github.coreglance") throws -> Data {
        let src = root.appendingPathComponent("zipsrc-\(UUID().uuidString)", isDirectory: true)
        try writeApp(at: src.appendingPathComponent("CoreGlance.app"), version: version, bundleID: bundleID)
        let zip = root.appendingPathComponent("made-\(UUID().uuidString).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        p.arguments = ["-c", "-k", "--keepParent", src.appendingPathComponent("CoreGlance.app").path, zip.path]
        try p.run(); p.waitUntilExit()
        return try Data(contentsOf: zip)
    }

    private func sha(_ data: Data) throws -> String {
        let f = root.appendingPathComponent("h-\(UUID().uuidString)")
        try data.write(to: f)
        return try UpdateLogic.sha256Hex(of: f)
    }

    private struct Setup { let target: URL; let tmp: URL; let downloader: FakeDownloader; let release: ReleaseInfo }

    private func setup(zip: Data, checksum: String? = nil) throws -> Setup {
        let target = root.appendingPathComponent("Apps/CoreGlance.app", isDirectory: true)
        try writeApp(at: target, version: "0.2.0", marker: "old")
        let tmp = root.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        let d = FakeDownloader()
        d.files[zipURL] = zip
        d.files[sumURL] = Data("\(try checksum ?? sha(zip))  CoreGlance.zip\n".utf8)
        let release = ReleaseInfo(version: "0.3.0", downloadURL: zipURL, pageURL: zipURL, checksumURL: sumURL)
        return Setup(target: target, tmp: tmp, downloader: d, release: release)
    }

    private func marker(_ app: URL) -> String? {
        (try? String(contentsOf: app.appendingPathComponent("Contents/marker"), encoding: .utf8))
    }

    private func assertFails(_ s: Setup, _ expected: UpdateInstallError, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await UpdateInstaller.install(s.release, into: s.target, bundleID: "io.github.coreglance", downloader: s.downloader, tempRoot: s.tmp)
            XCTFail("expected \(expected)", file: file, line: line)
        } catch {
            XCTAssertEqual(error as? UpdateInstallError, expected, file: file, line: line)
        }
        XCTAssertEqual(marker(s.target), "old", "the installed app must stay untouched", file: file, line: line)
        XCTAssertEqual((try? FileManager.default.contentsOfDirectory(atPath: s.tmp.path)) ?? ["?"], [], "scratch folder removed", file: file, line: line)
    }

    func testMatchingZipReplacesApp() async throws {
        let s = try setup(zip: try makeZip())
        try await UpdateInstaller.install(s.release, into: s.target, bundleID: "io.github.coreglance", downloader: s.downloader, tempRoot: s.tmp)
        XCTAssertEqual(marker(s.target), "new")
        let plist = NSDictionary(contentsOf: s.target.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(plist?["CFBundleShortVersionString"] as? String, "0.3.0")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.tmp.path), [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: s.target.deletingLastPathComponent().path), ["CoreGlance.app"], "no backup left")
    }

    func testWrongHashChangesNothing() async throws {
        await assertFails(try setup(zip: try makeZip(), checksum: emptySHA), .checksumMismatch)
    }

    func testMalformedChecksumFileChangesNothing() async throws {
        let s = try setup(zip: try makeZip())
        s.downloader.files[sumURL] = Data("not a hash".utf8)
        await assertFails(s, .badChecksumFile)
    }

    func testOtherBundleIDChangesNothing() async throws {
        await assertFails(try setup(zip: try makeZip(bundleID: "com.example.other")), .wrongBundleID)
    }

    func testOtherVersionChangesNothing() async throws {
        await assertFails(try setup(zip: try makeZip(version: "0.9.9")), .wrongVersion)
    }

    func testCorruptZipChangesNothing() async throws {
        let junk = Data("this is not a zip file".utf8)
        await assertFails(try setup(zip: junk), .unzipFailed)
    }

    func testDownloadFailureChangesNothing() async throws {
        let s = try setup(zip: try makeZip())
        s.downloader.files[zipURL] = nil
        await assertFails(s, .downloadFailed)
    }

    func testReleaseWithoutChecksumIsNotInstalled() async throws {
        var s = try setup(zip: try makeZip())
        s = Setup(target: s.target, tmp: s.tmp, downloader: s.downloader,
                  release: ReleaseInfo(version: "0.3.0", downloadURL: zipURL, pageURL: zipURL))
        await assertFails(s, .noChecksum)
    }

    func testNotInstallableOutsideAppBundleOrUnwritableFolder() throws {
        XCTAssertFalse(UpdateInstaller.canInstall(into: root.appendingPathComponent(".build/debug/CoreGlance")))
        XCTAssertTrue(UpdateInstaller.canInstall(into: root.appendingPathComponent("CoreGlance.app")))
        XCTAssertFalse(UpdateInstaller.canInstall(into: URL(fileURLWithPath: "/System/Applications/CoreGlance.app")))
    }

    func testReplaceSwapsAndRemovesBackup() throws {
        let target = root.appendingPathComponent("A/CoreGlance.app"), fresh = root.appendingPathComponent("fresh.app")
        try writeApp(at: target, version: "0.2.0", marker: "old")
        try writeApp(at: fresh, version: "0.3.0", marker: "new")
        try UpdateInstaller.replace(target, with: fresh)
        XCTAssertEqual(marker(target), "new")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path), ["CoreGlance.app"])
    }

    func testReplaceRollsBackWhenNewAppCannotBeCopied() throws {
        let target = root.appendingPathComponent("A/CoreGlance.app")
        try writeApp(at: target, version: "0.2.0", marker: "old")
        XCTAssertThrowsError(try UpdateInstaller.replace(target, with: root.appendingPathComponent("missing.app"))) {
            XCTAssertEqual($0 as? UpdateInstallError, .replaceFailed)
        }
        XCTAssertEqual(marker(target), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.deletingLastPathComponent().path), ["CoreGlance.app"], "backup moved back")
    }
}

@MainActor
final class UpdaterInstallTests: XCTestCase {
    func testInstallFailureShowsMessageAndDoesNotRelaunch() async throws {
        let name = "coreglance.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let zip = URL(string: "https://github.com/a/b/CoreGlance.zip")!
        let prefs = Preferences(defaults: defaults)
        prefs.knownRelease = ReleaseInfo(version: "0.3.0", downloadURL: zip, pageURL: zip,
                                         checksumURL: URL(string: "https://github.com/a/b/CoreGlance.zip.sha256"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("cg-upd-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let app = folder.appendingPathComponent("CoreGlance.app")
        var relaunched = false
        let updater = Updater(prefs: prefs, network: NoNetwork(), currentVersion: "0.2.0", downloader: FakeDownloader(),
                              appURL: app, bundleID: "io.github.coreglance", relaunch: { _ in relaunched = true })
        XCTAssertTrue(updater.canInstall(try XCTUnwrap(updater.availableUpdate)))
        await updater.installAvailable()
        XCTAssertEqual(updater.installState, .failed(UpdateInstallError.downloadFailed.message))
        XCTAssertFalse(relaunched)
    }

    func testNoButtonWithoutChecksumOrOutsideAppBundle() throws {
        let zip = URL(string: "https://github.com/a/b/CoreGlance.zip")!
        let updater = Updater(currentVersion: "0.2.0", appURL: URL(fileURLWithPath: "/tmp/.build/debug/CoreGlance"))
        let withSum = ReleaseInfo(version: "0.3.0", downloadURL: zip, pageURL: zip, checksumURL: zip)
        XCTAssertFalse(updater.canInstall(withSum), "binary is not inside an .app")
        let app = Updater(currentVersion: "0.2.0", appURL: FileManager.default.temporaryDirectory.appendingPathComponent("CoreGlance.app"))
        XCTAssertTrue(app.canInstall(withSum))
        XCTAssertFalse(app.canInstall(ReleaseInfo(version: "0.3.0", downloadURL: zip, pageURL: zip)))
    }
}

private struct NoNetwork: UpdateNetwork {
    func latestReleaseJSON() async throws -> Data { throw URLError(.notConnectedToInternet) }
}
