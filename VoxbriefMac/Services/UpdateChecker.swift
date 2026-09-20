import Foundation

/// Checks GitHub Releases for a newer macOS build than the one currently running.
///
/// Deliberately not Sparkle: at this app's current size, hitting GitHub's public Releases API
/// directly and opening the `.dmg`/release page in the browser is far less to set up and maintain
/// than an appcast feed plus EdDSA signing keys, for a "click to download" experience that's good
/// enough before this app has its own release pipeline. See `scripts/cut_release.sh` for how a
/// release (tag `vX.Y.Z`, e.g. the existing `v0.1.0`/`v0.2.0`) gets published today, driving the
/// iOS TestFlight workflow -- once a future Mac release step attaches a `.dmg` asset to one of
/// those same releases, `checkNow()` starts finding it with no changes needed here. Until then,
/// this will only ever report `.upToDate` (no macOS asset to offer), exactly as expected.
@MainActor
public final class UpdateChecker: ObservableObject {
    public static let shared = UpdateChecker()

    public struct AvailableUpdate: Equatable {
        public let version: String
        public let releasePageURL: URL
        public let downloadURL: URL
    }

    public enum CheckState: Equatable {
        case idle
        case checking
        case upToDate
        case updateAvailable(AvailableUpdate)
        case failed(String)
    }

    @Published public private(set) var state: CheckState = .idle
    @Published public private(set) var lastCheckedAt: Date?

    private let repoSlug: String
    private let currentVersion: String
    private let session: URLSession

    public init(
        repoSlug: String = "tianhaoz95/voxbrief",
        currentVersion: String = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0",
        session: URLSession = .shared
    ) {
        self.repoSlug = repoSlug
        self.currentVersion = currentVersion
        self.session = session
    }

    public func checkNow() async {
        state = .checking
        do {
            let url = URL(string: "https://api.github.com/repos/\(repoSlug)/releases/latest")!
            var request = URLRequest(url: url)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            let latestVersion = Self.stripLeadingV(release.tagName)

            guard let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") }),
                  let downloadURL = URL(string: dmgAsset.browserDownloadUrl),
                  let releasePageURL = URL(string: release.htmlUrl) else {
                // No macOS build attached to the latest release yet -- nothing to offer.
                state = .upToDate
                lastCheckedAt = Date()
                return
            }

            if Self.isVersion(latestVersion, newerThan: currentVersion) {
                state = .updateAvailable(AvailableUpdate(version: latestVersion, releasePageURL: releasePageURL, downloadURL: downloadURL))
            } else {
                state = .upToDate
            }
            lastCheckedAt = Date()
        } catch {
            state = .failed(error.localizedDescription)
            lastCheckedAt = Date()
        }
    }

    /// Pure, dependency-free SemVer-ish comparison so it's trivially sanity-checkable without a
    /// network call or a Mac test target: true if `candidate` is a strictly newer version than
    /// `current`. Missing/non-numeric components are treated as 0 rather than failing outright, so
    /// an unexpected tag format degrades to "not newer" instead of crashing the check.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let candidateParts = versionComponents(candidate)
        let currentParts = versionComponents(current)
        for index in 0..<max(candidateParts.count, currentParts.count) {
            let c = index < candidateParts.count ? candidateParts[index] : 0
            let d = index < currentParts.count ? currentParts[index] : 0
            if c != d { return c > d }
        }
        return false
    }

    static func versionComponents(_ version: String) -> [Int] {
        stripLeadingV(version).split(separator: ".").map { Int($0) ?? 0 }
    }

    static func stripLeadingV(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }
}

private struct GitHubRelease: Decodable {
    let tagName: String
    let htmlUrl: String
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case htmlUrl = "html_url"
        case assets
    }
}

private struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadUrl: String

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadUrl = "browser_download_url"
    }
}
