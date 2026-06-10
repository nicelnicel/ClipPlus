using System.Text.Json;
using System.Text.Json.Serialization;

namespace ClipPlus.Windows.Sync;

public enum ClipPlusMessageKind
{
    Hello,
    Text
}

public sealed class ClipPlusMessage
{
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
    public string CreatedAt { get; init; } = DateTimeOffset.UtcNow.ToString("O");

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
