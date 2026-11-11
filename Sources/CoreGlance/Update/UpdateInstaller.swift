import Foundation

enum UpdateInstallError: Error, Equatable {
    case notAnApp, notWritable, unzipFailed, appMissing, wrongBundleID, notNewer, replaceFailed
}

/// Replaces an installed `.app` with the one inside a zip. Any failure leaves the original untouched.
enum UpdateInstaller {
    static let bundleID = "io.github.coreglance"
    static let appName = "CoreGlance.app"

    static func canInstall(into target: URL) -> Bool {
        target.pathExtension == "app" && FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path)
    }

    /// `workDir` is an empty scratch folder owned by the caller.
    static func install(zip: URL, into target: URL, currentVersion: String, workDir: URL) throws {
        let fm = FileManager.default
        guard target.pathExtension == "app" else { throw UpdateInstallError.notAnApp }
        let parent = target.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: parent.path) else { throw UpdateInstallError.notWritable }

        // `ditto` keeps the ad-hoc signature, symlinks and permissions of the bundle.
        let extracted = workDir.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, extracted.path]) else { throw UpdateInstallError.unzipFailed }

        let newApp = extracted.appendingPathComponent(appName, isDirectory: true)
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw UpdateInstallError.appMissing
        }
        guard info["CFBundleIdentifier"] as? String == bundleID else { throw UpdateInstallError.wrongBundleID }
        guard let version = info["CFBundleShortVersionString"] as? String,
              UpdateLogic.isNewer(version, than: currentVersion) else { throw UpdateInstallError.notNewer }

        // Copy next to the target first (same volume), then swap by renaming;
        // the old bundle stays as a backup until the swap worked.
        let staged = parent.appendingPathComponent(".CoreGlance-update.app", isDirectory: true)
        let backup = parent.appendingPathComponent(".CoreGlance-backup.app", isDirectory: true)
        try? fm.removeItem(at: staged)
        try? fm.removeItem(at: backup)
        do { try fm.copyItem(at: newApp, to: staged) } catch {
            try? fm.removeItem(at: staged)
            throw UpdateInstallError.replaceFailed
        }
        do { try fm.moveItem(at: target, to: backup) } catch {
            try? fm.removeItem(at: staged)
            throw UpdateInstallError.replaceFailed
        }
        do { try fm.moveItem(at: staged, to: target) } catch {
            try? fm.moveItem(at: backup, to: target)
            try? fm.removeItem(at: staged)
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
