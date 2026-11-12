import Foundation

/// A GitHub release that can be installed: tag, the `CoreGlance.zip` asset and the release page.
struct ReleaseInfo: Equatable {
    let version: String
    let downloadURL: URL
    let pageURL: URL
}

/// Pure update logic: no network, no file system, so it can be tested with plain values.
enum UpdateLogic {
    static let assetName = "CoreGlance.zip"
    static let checkInterval: TimeInterval = 24 * 3600

    /// "v0.3.0" / "0.3" → [0, 3, 0]. Anything else (pre-release suffixes, text) is nil.
    static func parseVersion(_ text: String) -> [Int]? {
        var s = text.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        while numbers.count < 3 { numbers.append(0) }
        return numbers
    }

    /// Strictly higher version. An unparsable tag on either side means "no update".
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = parseVersion(candidate), let b = parseVersion(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    /// Reads the `releases/latest` JSON. Drafts, pre-releases, a missing `CoreGlance.zip`
    /// asset, a non-GitHub download host or broken JSON all give nil.
    static func parseRelease(_ data: Data) -> ReleaseInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["draft"] as? Bool != true, root["prerelease"] as? Bool != true,
              let tag = root["tag_name"] as? String, parseVersion(tag) != nil,
              let assets = root["assets"] as? [[String: Any]],
              let asset = assets.first(where: { $0["name"] as? String == assetName }),
              let urlText = asset["browser_download_url"] as? String, let download = URL(string: urlText),
              isTrustedHost(download)
        else { return nil }
        let page = (root["html_url"] as? String).flatMap(URL.init(string:)).flatMap { isTrustedHost($0) ? $0 : nil }
            ?? URL(string: "https://github.com/TheMartas29/CoreGlance/releases/latest")!
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        return ReleaseInfo(version: version, downloadURL: download, pageURL: page)
    }

    private static func isTrustedHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// Check at start (never checked before) and then at most once per 24 h; never when switched off.
    static func isCheckDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval || lastCheck > now
    }

    /// What Settings shows: the known release only counts while it is still newer than the running app.
    static func availableUpdate(known: ReleaseInfo?, current: String) -> ReleaseInfo? {
        guard let known, isNewer(known.version, than: current) else { return nil }
        return known
    }
}
