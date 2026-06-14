using System.IO;

namespace ClipPlus.Windows.Sync;

public sealed class RemoteClipboardReceiveGuard
{
    private static readonly HashSet<string> ImageFileExtensions = new(StringComparer.OrdinalIgnoreCase)
    {
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".bmp",
        ".tif",
        ".tiff",
        ".webp",
        ".heic",
        ".heif"
    };

    private readonly object syncLock = new();
    private readonly TimeSpan imageFileSuppressionInterval;
    private readonly Dictionary<string, DateTimeOffset> recentImageTimesByDeviceId = new(StringComparer.Ordinal);

    public RemoteClipboardReceiveGuard()
        : this(TimeSpan.FromSeconds(15))
    {
    }

    public RemoteClipboardReceiveGuard(TimeSpan imageFileSuppressionInterval)
    {
        this.imageFileSuppressionInterval = imageFileSuppressionInterval;
    }

    public void RecordRemoteImage(string senderDeviceId)
    {
        RecordRemoteImage(senderDeviceId, DateTimeOffset.UtcNow);
    }

    public void RecordRemoteImage(string senderDeviceId, DateTimeOffset now)
    {
        lock (syncLock)
        {
            recentImageTimesByDeviceId[senderDeviceId] = now;
        }
    }

    public bool ShouldSuppressFileOfferAfterRecentImage(
        string senderDeviceId,
        IReadOnlyList<FileTransferItem> files)
    {
        return ShouldSuppressFileOfferAfterRecentImage(senderDeviceId, files, DateTimeOffset.UtcNow);
    }

    public bool ShouldSuppressFileOfferAfterRecentImage(
        string senderDeviceId,
        IReadOnlyList<FileTransferItem> files,
        DateTimeOffset now)
    {
        if (!IsSingleImageFileOffer(files))
        {
            return false;
        }

        lock (syncLock)
        {
            return recentImageTimesByDeviceId.TryGetValue(senderDeviceId, out var imageTime)
                && now - imageTime <= imageFileSuppressionInterval;
        }
    }

    private static bool IsSingleImageFileOffer(IReadOnlyList<FileTransferItem> files)
    {
        if (files.Count != 1)
        {
            return false;
        }

        var file = files[0];
        return !file.IsDirectory
            && file.ByteSize > 0
            && ImageFileExtensions.Contains(Path.GetExtension(file.RelativePath));
    }
}
