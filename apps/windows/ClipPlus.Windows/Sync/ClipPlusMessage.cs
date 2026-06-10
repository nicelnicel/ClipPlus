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
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateHelloMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName
        ) ?? throw new InvalidOperationException("Rust core library is unavailable; cannot create hello message.");

        return FromJson(json);
    }

    public static ClipPlusMessage CreateTrust(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string approvedDeviceId)
    {
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateTrustMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName,
            approvedDeviceId
        ) ?? throw new InvalidOperationException("Rust core library is unavailable; cannot create trust message.");

        return FromJson(json);
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

        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateImageMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName,
            pngData
        ) ?? throw new InvalidOperationException("Rust core library is unavailable; cannot create image clipboard message.");

        return FromJson(json);
    }

    public static ClipPlusMessage CreateText(
        string groupId,
        string senderDeviceId,
        string senderDeviceName,
        string text)
    {
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateTextMessageJson(
            groupId,
            senderDeviceId,
            senderDeviceName,
            text
        ) ?? throw new InvalidOperationException("Rust core library is unavailable; cannot create text clipboard message.");

        return FromJson(json);
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
