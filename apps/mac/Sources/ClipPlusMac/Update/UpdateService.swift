import Foundation

protocol AppUpdateServicing {
    func checkAndDownloadLatest(progress: @escaping @MainActor (Double) -> Void) async throws -> UpdateCheckResult
    func installAndRelaunch(_ downloadedUpdate: DownloadedUpdate) throws -> Never
}

struct UpdateService: AppUpdateServicing {
    private let releaseClient: GitHubReleaseClient
    private let downloader: UpdateDownloader
    private let installer: MacUpdateInstaller
    private let logger: ClipPlusLogger

    init(
        releaseClient: GitHubReleaseClient = GitHubReleaseClient(),
        downloader: UpdateDownloader = UpdateDownloader(),
        installer: MacUpdateInstaller = MacUpdateInstaller(),
        logger: ClipPlusLogger = ClipPlusLogger()
    ) {
        self.releaseClient = releaseClient
        self.downloader = downloader
        self.installer = installer
        self.logger = logger
    }

    func checkAndDownloadLatest(progress: @escaping @MainActor (Double) -> Void) async throws -> UpdateCheckResult {
        guard let currentVersion = UpdateVersion(AppVersion.current) else {
            throw UpdateError.invalidVersion
        }

        do {
            let release = try await releaseClient.fetchLatestRelease()
            let asset = try GitHubReleaseClient.selectMacAsset(from: release, currentVersion: currentVersion)
            logger.info("update available version=\(asset.version.description) asset=\(asset.name)")
            let downloadedUpdate = try await downloader.download(asset: asset, progress: progress)
            logger.info("update downloaded version=\(downloadedUpdate.version.description)")
            return .downloaded(downloadedUpdate)
        } catch UpdateError.upToDate {
            logger.info("update check up to date current=\(currentVersion.description)")
            return .upToDate
        }
    }

    func installAndRelaunch(_ downloadedUpdate: DownloadedUpdate) throws -> Never {
        try installer.installAndRelaunch(downloadedUpdate: downloadedUpdate)
    }
}
