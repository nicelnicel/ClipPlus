using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClipPlus.Windows.Sync;

public enum ClipPlusMessageKind
{
    Hello,
    Trust,
    Text,
    Image,
    FileOffer
}

public sealed record FileTransferItem(string RelativePath, long ByteSize, bool IsDirectory);

public sealed class ClipPlusMessage
{
    public const int MaxInlineImageBytes = 32 * 1024;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase) }
    };

    public ClipPlusMessageKind Kind { get; init; }
    public int ProtocolVersion { get; init; } = 1;
    public string GroupId { get; init; } = string.Empty;
    public string SenderDeviceId { get; init; } = string.Empty;
    public string SenderDeviceName { get; init; } = string.Empty;
    public string EventId { get; init; } = Guid.NewGuid().ToString();
    public string? Text { get; init; }
    public string? ImageBase64 { get; init; }
    public int? ImageByteSize { get; init; }
    public string? ImageContentHash { get; init; }
    public string? ApprovedDeviceId { get; init; }
    public string? TransferId { get; init; }
    public IReadOnlyList<FileTransferItem>? Files { get; init; }
    public int? ArchivePort { get; init; }
    public string CreatedAt { get; init; } = DateTimeOffset.UtcNow.ToString("O");

    [JsonIgnore]
    public byte[]? DecodedImageData => ImageBase64 is null ? null : Convert.FromBase64String(ImageBase64);

    public static ClipPlusMessage CreateHello(
        string groupId,
        string senderDeviceId,
        string senderDeviceName)
    {
        return new ClipPlusMessage
        {
            Kind = ClipPlusMessageKind.Hello,
            GroupId = groupId,
            SenderDeviceId = senderDeviceId,
            SenderDeviceName = senderDeviceName
        };
    }

    public static ClipPlusMessage CreateTrust(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string approvedDeviceId)
    {
        return new ClipPlusMessage
        {
            Kind = ClipPlusMessageKind.Trust,
            GroupId = groupId,
            SenderDeviceId = senderDeviceId,
            SenderDeviceName = senderDeviceName,
            ApprovedDeviceId = approvedDeviceId
        };
    }

    public static ClipPlusMessage CreateFileOffer(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string transferId,
        IReadOnlyList<FileTransferItem> files,
        int archivePort)
    {
        return new ClipPlusMessage
        {
            Kind = ClipPlusMessageKind.FileOffer,
            GroupId = groupId,
            SenderDeviceId = senderDeviceId,
            SenderDeviceName = senderDeviceName,
            TransferId = transferId,
            Files = files,
            ArchivePort = archivePort
        };
    }

    public static ClipPlusMessage? CreateImage(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        byte[] pngData)
    {
        if (pngData.Length == 0 || pngData.Length > MaxInlineImageBytes)
        {
            return null;
        }

        return new ClipPlusMessage
        {
            Kind = ClipPlusMessageKind.Image,
            GroupId = groupId,
            SenderDeviceId = senderDeviceId,
            SenderDeviceName = senderDeviceName,
            ImageBase64 = Convert.ToBase64String(pngData),
            ImageByteSize = pngData.Length,
            ImageContentHash = Convert.ToHexString(SHA256.HashData(pngData)).ToLowerInvariant()
        };
    }

    public static ClipPlusMessage CreateText(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string text)
    {
        return new ClipPlusMessage
        {
            Kind = ClipPlusMessageKind.Text,
            GroupId = groupId,
            SenderDeviceId = senderDeviceId,
            SenderDeviceName = senderDeviceName,
            Text = text
        };
    }

    public string ToJson()
    {
        return JsonSerializer.Serialize(this, JsonOptions);
    }

    public static ClipPlusMessage FromJson(string json)
    {
        return JsonSerializer.Deserialize<ClipPlusMessage>(json, JsonOptions)
            ?? throw new InvalidOperationException("ClipPlus message JSON is empty");
    }
}
