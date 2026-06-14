namespace ClipPlus.Windows.Update;

using System.IO;
using System.Net.Http;
using System.Security.Cryptography;

public sealed class UpdateDownloader
{
    private readonly HttpClient httpClient;
    private readonly string localAppDataDirectory;

    public UpdateDownloader(HttpClient? httpClient = null, string? localAppDataDirectory = null)
    {
        this.httpClient = httpClient ?? new HttpClient();
        this.localAppDataDirectory = localAppDataDirectory
            ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
    }

    public async Task<DownloadedUpdate> DownloadAsync(
        SelectedUpdateAsset asset,
        Action<double>? progress = null,
        CancellationToken cancellationToken = default)
    {
        var updateDirectory = Path.Combine(
            localAppDataDirectory,
            "ClipPlus",
            "Updates",
            $"v{asset.Version}"
        );
        Directory.CreateDirectory(updateDirectory);

        var finalPath = Path.Combine(updateDirectory, asset.Name);
        var partialPath = $"{finalPath}.partial";
        File.Delete(partialPath);
        File.Delete(finalPath);

        using var response = await httpClient.GetAsync(
            asset.DownloadUrl,
            HttpCompletionOption.ResponseHeadersRead,
            cancellationToken
        );
        if (!response.IsSuccessStatusCode)
        {
            throw new UpdateException(UpdateErrorKind.DownloadFailed);
        }

        var totalBytes = response.Content.Headers.ContentLength;
        await using (var input = await response.Content.ReadAsStreamAsync(cancellationToken))
        await using (var output = File.Create(partialPath))
        {
            var buffer = new byte[64 * 1024];
            long copiedBytes = 0;
            int readBytes;
            while ((readBytes = await input.ReadAsync(buffer, cancellationToken)) > 0)
            {
                await output.WriteAsync(buffer.AsMemory(0, readBytes), cancellationToken);
                copiedBytes += readBytes;
                if (totalBytes is > 0)
                {
                    progress?.Invoke(Math.Clamp(copiedBytes / (double)totalBytes.Value, 0, 1));
                }
            }
        }

        VerifySha256(partialPath, asset.Sha256Hex);
        File.Move(partialPath, finalPath, overwrite: true);
        progress?.Invoke(1);
        return new DownloadedUpdate(asset.Version, asset.Name, finalPath);
    }

    public static void VerifySha256(string filePath, string expectedHex)
    {
        using var stream = File.OpenRead(filePath);
        var digest = Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
        if (!string.Equals(digest, expectedHex, StringComparison.OrdinalIgnoreCase))
        {
            throw new UpdateException(UpdateErrorKind.Sha256Mismatch);
        }
    }
}
