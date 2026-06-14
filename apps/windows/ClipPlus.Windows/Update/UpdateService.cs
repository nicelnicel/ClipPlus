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
            var asset = GitHubReleaseClient.SelectWindowsAsset(release, currentVersion);
            logger.Info($"update available version={asset.Version} asset={asset.Name}");
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
