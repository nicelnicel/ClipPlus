import Foundation

enum UpdateError: Error, Equatable, LocalizedError {
    case invalidVersion
    case upToDate
    case missingAsset
    case missingDigest
    case invalidDigest
    case sha256Mismatch
    case unsupportedRuntime
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidVersion:
            return "更新版本格式无效"
        case .upToDate:
            return "已是最新版本"
        case .missingAsset:
            return "当前平台没有可用更新包"
        case .missingDigest:
            return "更新包缺少校验信息"
        case .invalidDigest:
            return "更新包校验信息无效"
        case .sha256Mismatch:
            return "更新包校验失败"
        case .unsupportedRuntime:
            return "当前运行方式不支持自动更新"
        case .downloadFailed:
            return "更新包下载失败"
        }
    }
}

struct UpdateVersion: Comparable, Equatable, CustomStringConvertible {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingPrefix("v")
        let parts = normalized.split(separator: ".")
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]) else {
            return nil
        }

        self.major = major
        self.minor = minor
        self.patch = patch
    }

    var description: String {
        "\(major).\(minor).\(patch)"
    }

    static func < (lhs: UpdateVersion, rhs: UpdateVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}

struct GitHubRelease: Decodable {
    let tagName: String
    let draft: Bool
    let prerelease: Bool
    let assets: [GitHubReleaseAsset]

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case draft
        case prerelease
        case assets
    }
}

struct GitHubReleaseAsset: Decodable {
    let name: String
    let browserDownloadURL: URL
    let digest: String?
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
        case digest
        case size
    }
}

struct SelectedUpdateAsset: Equatable {
    let version: UpdateVersion
    let name: String
    let downloadURL: URL
    let sha256Hex: String
    let size: Int64
}

struct DownloadedUpdate: Equatable {
    let version: UpdateVersion
    let assetName: String
    let fileURL: URL
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case downloaded(DownloadedUpdate)
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
