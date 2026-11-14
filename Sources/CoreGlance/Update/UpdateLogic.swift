import CryptoKit
import Foundation

/// A GitHub release that can be installed: tag, the `CoreGlance.zip` asset and the release page.
/// `checksumURL` is the `CoreGlance.zip.sha256` asset; without it the update is not installed in-app.
struct ReleaseInfo: Equatable {
    let version: String
    let downloadURL: URL
    let pageURL: URL
    var checksumURL: URL? = nil
}

/// Pure update logic: no network, no file system, so it can be tested with plain values.
enum UpdateLogic {
    static let assetName = "CoreGlance.zip"
    static let checksumAssetName = "CoreGlance.zip.sha256"

    /// Hash from a `shasum -a 256` line ("<64 hex>  CoreGlance.zip"; the file name is optional but,
    /// when present, must be `CoreGlance.zip`). Lower-cased; anything malformed is nil.
    static func parseChecksum(_ text: String) -> String? {
        guard let line = text.split(whereSeparator: \.isNewline)
            .map({ $0.trimmingCharacters(in: .whitespaces) }).first(where: { !$0.isEmpty }) else { return nil }
        let tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard (1...2).contains(tokens.count) else { return nil }
        let hash = tokens[0].lowercased()
        guard hash.count == 64, hash.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        if tokens.count == 2 {
            let name = tokens[1].hasPrefix("*") ? String(tokens[1].dropFirst()) : String(tokens[1])
            guard name == assetName else { return nil }
        }
        return hash
    }

    /// True when the checksum file is well-formed and names exactly this digest.
    static func checksumMatches(_ checksumText: String, digest: String) -> Bool {
        guard let expected = parseChecksum(checksumText) else { return false }
        return expected == digest.lowercased()
    }

    /// SHA-256 of a file as lower-case hex, read in chunks.
    static func sha256Hex(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
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
        let checksum = assets.first(where: { $0["name"] as? String == checksumAssetName })
            .flatMap { $0["browser_download_url"] as? String }.flatMap(URL.init(string:))
            .flatMap { isTrustedHost($0) ? $0 : nil }
        return ReleaseInfo(version: version, downloadURL: download, pageURL: page, checksumURL: checksum)
    }

    static func isTrustedHost(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com") || host.hasSuffix(".githubusercontent.com")
    }

    /// Check at start (never checked before) and then at most once per 24 h; never when switched off.
    static func isCheckDue(enabled: Bool, lastCheck: Date?, now: Date) -> Bool {
        guard enabled else { return false }
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval || lastCheck > now
    }

    /// Install right now without a click: only with the option on, an installable newer release,
    /// and not for a version that already failed in this session.
    static func shouldInstallNow(autoInstall: Bool, canInstall: Bool, available: ReleaseInfo?, failedVersion: String?) -> Bool {
        guard autoInstall, canInstall, let available else { return false }
        return available.version != failedVersion
    }

    /// Why the "Install updates automatically" switch is disabled (nil = usable).
    static func autoInstallBlocker(autoUpdate: Bool, canReplaceSelf: Bool) -> String? {
        if !autoUpdate { return "Turn on “Check for updates automatically” first." }
        if !canReplaceSelf { return "CoreGlance is not in a writable folder, so it cannot replace itself." }
        return nil
    }

    /// What Settings shows: the known release only counts while it is still newer than the running app.
    static func availableUpdate(known: ReleaseInfo?, current: String) -> ReleaseInfo? {
        guard let known, isNewer(known.version, than: current) else { return nil }
        return known
    }
}
