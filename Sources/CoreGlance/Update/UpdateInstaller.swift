import Foundation

/// Network boundary of the installer (replaced by a fake in tests): saves `url` to `file`.
protocol UpdateDownloader {
    func download(_ url: URL, to file: URL) async throws
}

struct GitHubDownloader: UpdateDownloader {
    func download(_ url: URL, to file: URL) async throws {
        guard UpdateLogic.isTrustedHost(url) else { throw URLError(.badURL) }
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.setValue("CoreGlance", forHTTPHeaderField: "User-Agent")
        let (temp, response) = try await URLSession.shared.download(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let final = response.url, UpdateLogic.isTrustedHost(final) else {
            try? FileManager.default.removeItem(at: temp)
            throw URLError(.badServerResponse)
        }
        try FileManager.default.moveItem(at: temp, to: file)
    }
}

enum UpdateInstallError: Error, Equatable {
    case notInstallable, noChecksum, downloadFailed, badChecksumFile, checksumMismatch
    case unzipFailed, appMissing, wrongBundleID, wrongVersion, replaceFailed

    /// Short text for Settings.
    var message: String {
        switch self {
        case .notInstallable: return "This copy of CoreGlance cannot replace itself. Use the release page."
        case .noChecksum: return "This release has no checksum file. Use the release page."
        case .downloadFailed: return "Download failed. Try again later."
        case .badChecksumFile: return "The checksum file is not valid. Nothing was installed."
        case .checksumMismatch: return "The download does not match its checksum. Nothing was installed."
        case .unzipFailed: return "The download could not be unpacked. Nothing was installed."
        case .appMissing: return "The download does not contain CoreGlance.app. Nothing was installed."
        case .wrongBundleID: return "The downloaded app is a different app. Nothing was installed."
        case .wrongVersion: return "The downloaded app has an unexpected version. Nothing was installed."
        case .replaceFailed: return "Replacing the app failed; the old version is kept."
        }
    }
}

/// Downloads a release, verifies it and replaces the installed `.app`. Any failure leaves the
/// original untouched and removes the scratch folder.
enum UpdateInstaller {
    static let appName = "CoreGlance.app"

    /// Only a running `.app` bundle in a writable folder can replace itself.
    static func canInstall(into target: URL) -> Bool {
        target.pathExtension == "app"
            && FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    static func install(_ release: ReleaseInfo, into target: URL, bundleID: String,
                        downloader: UpdateDownloader, tempRoot: URL = FileManager.default.temporaryDirectory) async throws {
        guard canInstall(into: target) else { throw UpdateInstallError.notInstallable }
        guard let checksumURL = release.checksumURL else { throw UpdateInstallError.noChecksum }
        let fm = FileManager.default
        let work = tempRoot.appendingPathComponent("CoreGlance-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zip = work.appendingPathComponent(UpdateLogic.assetName)
        let sum = work.appendingPathComponent(UpdateLogic.checksumAssetName)
        do {
            try await downloader.download(release.downloadURL, to: zip)
            try await downloader.download(checksumURL, to: sum)
        } catch { throw UpdateInstallError.downloadFailed }

        guard let text = try? String(contentsOf: sum, encoding: .utf8), UpdateLogic.parseChecksum(text) != nil else {
            throw UpdateInstallError.badChecksumFile
        }
        guard let digest = try? UpdateLogic.sha256Hex(of: zip), UpdateLogic.checksumMatches(text, digest: digest) else {
            throw UpdateInstallError.checksumMismatch
        }

        // `ditto` keeps the ad-hoc signature, symlinks and permissions of the bundle.
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path]) else { throw UpdateInstallError.unzipFailed }

        let newApp = extracted.appendingPathComponent(appName, isDirectory: true)
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw UpdateInstallError.appMissing
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateInstallError.wrongBundleID }
        guard info["CFBundleShortVersionString"] as? String == release.version else { throw UpdateInstallError.wrongVersion }
        try replace(target, with: newApp)
    }

    /// Old bundle → backup next to it, new bundle in, backup removed. On failure the backup goes back.
    static func replace(_ target: URL, with newApp: URL) throws {
        let fm = FileManager.default
        let backup = target.deletingLastPathComponent().appendingPathComponent(".CoreGlance-backup.app", isDirectory: true)
        try? fm.removeItem(at: backup)
        do { try fm.moveItem(at: target, to: backup) } catch { throw UpdateInstallError.replaceFailed }
        do { try fm.copyItem(at: newApp, to: target) } catch {
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: backup, to: target)
            throw UpdateInstallError.replaceFailed
        }
        try? fm.removeItem(at: backup)
    }

    private static func run(_ path: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
