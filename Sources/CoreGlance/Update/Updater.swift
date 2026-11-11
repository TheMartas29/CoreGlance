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

    init(prefs: Preferences = .shared,
         network: UpdateNetwork = GitHubNetwork(),
         currentVersion: String? = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) {
        self.prefs = prefs
        self.network = network
        self.currentVersion = currentVersion
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
        let release: ReleaseInfo?
        do {
            release = UpdateLogic.parseRelease(try await network.latestReleaseJSON())
        } catch {
            Self.log.error("update check failed: \(error.localizedDescription)")
            return
        }
        objectWillChange.send()
        prefs.lastUpdateCheck = now
        if let release, UpdateLogic.isNewer(release.version, than: currentVersion) {
            prefs.knownRelease = release
            Self.log.info("update \(release.version) available")
        } else {
            prefs.knownRelease = nil
        }
    }
}
