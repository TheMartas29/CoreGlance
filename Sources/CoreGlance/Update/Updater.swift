import AppKit
import Foundation
import os

/// Network boundary of the updater (replaced by a fake in tests).
protocol UpdateNetwork {
    func latestReleaseJSON() async throws -> Data
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
}

/// Looks for a newer GitHub release while the user allows it. Fail-soft: errors are only logged.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    private static let log = Logger(subsystem: "io.github.coreglance", category: "update")

    private let prefs: Preferences
    private let network: UpdateNetwork
    private let currentVersion: String?
    private var busy = false
    private var timer: Timer?

    enum InstallState: Equatable { case idle, installing, failed(String) }
    @Published private(set) var installState = InstallState.idle
    private let downloader: UpdateDownloader
    private let appURL: URL
    private let bundleID: String
    private let relaunch: (URL) -> Void

    init(prefs: Preferences = .shared,
         network: UpdateNetwork = GitHubNetwork(),
         currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
         downloader: UpdateDownloader = GitHubDownloader(),
         appURL: URL = Bundle.main.bundleURL,
         bundleID: String = Bundle.main.bundleIdentifier ?? "",
         relaunch: @escaping (URL) -> Void = Updater.startNewAndQuit) {
        self.prefs = prefs
        self.network = network
        self.currentVersion = currentVersion
        self.downloader = downloader
        self.appURL = appURL
        self.bundleID = bundleID
        self.relaunch = relaunch
    }

    /// The button is offered only when the release has a checksum and this app can replace itself.
    func canInstall(_ release: ReleaseInfo) -> Bool {
        release.checksumURL != nil && UpdateInstaller.canInstall(into: appURL)
    }

    /// Install and restart. Fail-soft: an error becomes a message in Settings and the app keeps running.
    func installAvailable() async {
        guard let release = availableUpdate, canInstall(release), installState != .installing else { return }
        installState = .installing
        do {
            try await UpdateInstaller.install(release, into: appURL, bundleID: bundleID, downloader: downloader)
        } catch {
            let text = (error as? UpdateInstallError)?.message ?? "Update failed. The old version is kept."
            Self.log.error("install failed: \(text)")
            installState = .failed(text)
            return
        }
        installState = .idle
        relaunch(appURL)
    }

    /// Starts the replaced app after a short delay (so this instance has quit), then quits this one.
    nonisolated static func startNewAndQuit(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; exec /usr/bin/open \"$1\"", "sh", app.path]
        try? p.run()
        DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
    }

    /// A newer release known from an earlier check (also while auto-update is off).
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
        let release: ReleaseInfo
        do {
            guard let parsed = UpdateLogic.parseRelease(try await network.latestReleaseJSON()) else {
                // Unreadable answer (no zip asset, rate-limit message, broken JSON): not a completed check;
                // keep an earlier offer and retry on the next hourly tick.
                Self.log.error("update check: unreadable release answer")
                return
            }
            release = parsed
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription)")
            return
        }
        objectWillChange.send()
        prefs.lastUpdateCheck = now
        if UpdateLogic.isNewer(release.version, than: currentVersion) {
            prefs.knownRelease = release
            Self.log.info("update \(release.version) available")
        } else {
            prefs.knownRelease = nil
        }
    }
}
