import AppKit
import os

/// Network boundary of the updater (replaced by a fake in tests).
protocol UpdateNetwork {
    func latestReleaseJSON() async throws -> Data
    func download(_ url: URL, to file: URL) async throws
}

struct GitHubNetwork: UpdateNetwork {
    static let latest = URL(string: "https://api.github.com/repos/TheMartas29/CoreGlance/releases/latest")!

    func latestReleaseJSON() async throws -> Data {
        var request = URLRequest(url: Self.latest, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CoreGlance", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    func download(_ url: URL, to file: URL) async throws {
        let (temp, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try FileManager.default.moveItem(at: temp, to: file)
    }
}

/// Looks for a newer GitHub release and installs it, if the user allows it. Fail-soft: errors are only logged.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    private static let log = Logger(subsystem: "io.github.coreglance", category: "update")

    private let prefs: Preferences
    private let network: UpdateNetwork
    private let currentVersion: String?
    private let target: URL
    private let relaunch: (URL) -> Void
    private var busy = false
    private var timer: Timer?
    @Published private(set) var installing = false

    init(prefs: Preferences = .shared,
         network: UpdateNetwork = GitHubNetwork(),
         currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
         target: URL = Bundle.main.bundleURL,
         relaunch: @escaping (URL) -> Void = Updater.relaunchApp) {
        self.prefs = prefs
        self.network = network
        self.currentVersion = currentVersion
        self.target = target
        self.relaunch = relaunch
    }

    /// A newer release known from an earlier check (also while auto-install is off).
    var availableUpdate: ReleaseInfo? {
        guard let currentVersion else { return nil }
        return UpdateLogic.availableUpdate(known: prefs.knownRelease, current: currentVersion)
    }

    /// Checks now, then hourly; each check only talks to GitHub when it is due.
    func start() {
        Task { await tick() }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.tick() }
        }
    }

    func tick(now: Date = Date()) async {
        guard let currentVersion, !busy,
              UpdateLogic.isCheckDue(enabled: prefs.autoUpdate, lastCheck: prefs.lastUpdateCheck, now: now) else { return }
        busy = true
        defer { busy = false }
        let release: ReleaseInfo?
        do {
            release = UpdateLogic.parseRelease(try await network.latestReleaseJSON())
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription)")
            return
        }
        objectWillChange.send()
        prefs.lastUpdateCheck = now
        guard let release, UpdateLogic.isNewer(release.version, than: currentVersion) else {
            prefs.knownRelease = nil
            return
        }
        prefs.knownRelease = release
        guard UpdateInstaller.canInstall(into: target) else {
            Self.log.info("update \(release.version) available, \(self.target.path) is not writable")
            return
        }
        await install(release, currentVersion: currentVersion)
    }

    private func install(_ release: ReleaseInfo, currentVersion: String) async {
        installing = true
        defer { installing = false }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("CoreGlance-update-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: work) }
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent(UpdateLogic.assetName)
            try await network.download(release.downloadURL, to: zip)
            try UpdateInstaller.install(zip: zip, into: target, currentVersion: currentVersion, workDir: work)
            Self.log.info("installed \(release.version), restarting")
            relaunch(target)
        } catch {
            Self.log.error("update install failed: \(String(describing: error))")
        }
    }

    nonisolated static func relaunchApp(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", app.path]
        try? p.run()
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }
}
