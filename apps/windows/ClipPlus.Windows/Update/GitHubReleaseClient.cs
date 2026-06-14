namespace ClipPlus.Windows.Update;

using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

public sealed class GitHubReleaseClient
{
    public static readonly Uri LatestReleaseUri = new("https://github.com/nicelnicel/ClipPlus/releases/latest/download/clipplus-update.json");

    private readonly HttpClient httpClient;

    public GitHubReleaseClient(HttpClient? httpClient = null)
    {
        this.httpClient = httpClient ?? new HttpClient();
    }

    public static GitHubRelease DecodeRelease(string json)
    {
        return JsonSerializer.Deserialize<GitHubRelease>(json)
            ?? throw new UpdateException(UpdateErrorKind.InvalidVersion);
    }

    public static SelectedUpdateAsset SelectWindowsAsset(GitHubRelease release, UpdateVersion currentVersion)
    {
        return SelectWindowsAsset(
            release,
            currentVersion,
            WindowsUpdatePackageKindDetector.DetectCurrent()
        );
    }

    public static SelectedUpdateAsset SelectWindowsAsset(
        GitHubRelease release,
        UpdateVersion currentVersion,
        WindowsUpdatePackageKind packageKind)
    {
        if (release.Draft || release.Prerelease || !UpdateVersion.TryParse(release.TagName, out var releaseVersion))
        {
            throw new UpdateException(UpdateErrorKind.InvalidVersion);
        }

        if (releaseVersion.CompareTo(currentVersion) <= 0)
        {
            throw new UpdateException(UpdateErrorKind.UpToDate);
        }

        var assetName = packageKind switch
        {
            WindowsUpdatePackageKind.RuntimeDependent => "ClipPlus-Windows-x64-runtime-dependent.exe",
            _ => "ClipPlus-Windows-x64-full.exe"
        };
        var asset = release.Assets.FirstOrDefault(asset => asset.Name == assetName)
            ?? throw new UpdateException(UpdateErrorKind.MissingAsset);
        var digest = NormalizedSha256Digest(asset.Digest);
        return new SelectedUpdateAsset(
            releaseVersion,
            asset.Name,
            asset.BrowserDownloadUrl,
            digest,
            asset.Size
        );
    }

    public async Task<GitHubRelease> FetchLatestReleaseAsync(CancellationToken cancellationToken = default)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, LatestReleaseUri);
        request.Headers.UserAgent.ParseAdd("ClipPlus");
        request.Headers.Accept.ParseAdd("application/json");
        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new UpdateException(UpdateErrorKind.DownloadFailed);
        }

        var json = await response.Content.ReadAsStringAsync(cancellationToken);
        return DecodeRelease(json);
    }

    private static string NormalizedSha256Digest(string? digest)
    {
        if (string.IsNullOrWhiteSpace(digest))
        {
            throw new UpdateException(UpdateErrorKind.MissingDigest);
        }

        var normalized = digest.Trim().ToLowerInvariant();
        if (normalized.StartsWith("sha256:", StringComparison.Ordinal))
        {
            normalized = normalized["sha256:".Length..];
        }

        if (!Regex.IsMatch(normalized, "^[0-9a-f]{64}$"))
        {
            throw new UpdateException(UpdateErrorKind.InvalidDigest);
        }

        return normalized;
    }
}

public sealed record GitHubRelease(
    [property: JsonPropertyName("tag_name")] string TagName,
    [property: JsonPropertyName("draft")] bool Draft,
    [property: JsonPropertyName("prerelease")] bool Prerelease,
    [property: JsonPropertyName("assets")] IReadOnlyList<GitHubReleaseAsset> Assets
);

public sealed record GitHubReleaseAsset(
    [property: JsonPropertyName("name")] string Name,
    [property: JsonPropertyName("browser_download_url")] Uri BrowserDownloadUrl,
    [property: JsonPropertyName("digest")] string? Digest,
    [property: JsonPropertyName("size")] long Size
);
