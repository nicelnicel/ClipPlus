import Foundation

struct GitHubReleaseClient {
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/nicelnicel/ClipPlus/releases/latest")!

    static func decodeRelease(from data: Data) throws -> GitHubRelease {
        try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    static func selectMacAsset(
        from release: GitHubRelease,
        currentVersion: UpdateVersion
    ) throws -> SelectedUpdateAsset {
        guard !release.draft, !release.prerelease,
              let releaseVersion = UpdateVersion(release.tagName) else {
            throw UpdateError.invalidVersion
        }

        guard releaseVersion > currentVersion else {
            throw UpdateError.upToDate
        }

        guard let asset = release.assets.first(where: { $0.name == "ClipPlus-macOS.dmg" }) else {
            throw UpdateError.missingAsset
        }

        let digest = try normalizedSha256Digest(asset.digest)
        return SelectedUpdateAsset(
            version: releaseVersion,
            name: asset.name,
            downloadURL: asset.browserDownloadURL,
            sha256Hex: digest,
            size: asset.size
        )
    }

    func fetchLatestRelease() async throws -> GitHubRelease {
        var request = URLRequest(url: Self.latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ClipPlus", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw UpdateError.downloadFailed
        }

        return try Self.decodeRelease(from: data)
    }

    private static func normalizedSha256Digest(_ digest: String?) throws -> String {
        guard let digest, !digest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UpdateError.missingDigest
        }

        let normalized = digest
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "sha256:", with: "")
        guard normalized.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil else {
            throw UpdateError.invalidDigest
        }

        return normalized
    }
}
