namespace ClipPlus.Windows.Update;

using ClipPlus.Windows.Diagnostics;

public sealed class UpdateService
{
    private readonly GitHubReleaseClient releaseClient;
    private readonly UpdateDownloader downloader;
    private readonly WindowsUpdateInstaller installer;
    private readonly ClipPlusLogger logger;

    public UpdateService(
        GitHubReleaseClient? releaseClient = null,
        UpdateDownloader? downloader = null,
        WindowsUpdateInstaller? installer = null,
        ClipPlusLogger? logger = null)
    {
        this.releaseClient = releaseClient ?? new GitHubReleaseClient();
        this.downloader = downloader ?? new UpdateDownloader();
        this.installer = installer ?? new WindowsUpdateInstaller();
        this.logger = logger ?? new ClipPlusLogger();
    }

    public async Task<UpdateCheckResult> CheckAndDownloadLatestAsync(
        Action<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var currentVersion = UpdateVersion.Parse(AppVersion.Current);
        try
        {
            var release = await releaseClient.FetchLatestReleaseAsync(cancellationToken);
            var packageKind = WindowsUpdatePackageKindDetector.DetectCurrent();
            if (packageKind != WindowsUpdatePackageKind.RuntimeDependent
                && !DotNetDesktopRuntimeDetector.HasDotNet8DesktopRuntime())
            {
                logger.Error($"windows update blocked because .NET 8 Desktop Runtime is missing package_kind={packageKind}");
                throw new UpdateException(UpdateErrorKind.UnsupportedRuntime);
            }

            var asset = GitHubReleaseClient.SelectWindowsAsset(release, currentVersion, packageKind);
            logger.Info($"update available version={asset.Version} asset={asset.Name} package_kind={packageKind}");
            var downloadedUpdate = await downloader.DownloadAsync(asset, progress, cancellationToken);
            logger.Info($"update downloaded version={downloadedUpdate.Version}");
            return UpdateCheckResult.Downloaded(downloadedUpdate);
        }
        catch (UpdateException error) when (error.Kind == UpdateErrorKind.UpToDate)
        {
            logger.Info($"update check up to date current={currentVersion}");
            return UpdateCheckResult.UpToDate();
        }
    }

    public void InstallAndRelaunch(DownloadedUpdate downloadedUpdate)
    {
        installer.InstallAndRelaunch(downloadedUpdate);
    }
}
