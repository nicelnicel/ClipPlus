using System.ComponentModel;
using System.Runtime.CompilerServices;
using ClipPlus.Windows.Sync;

namespace ClipPlus.Windows.Settings;

public sealed record PreparedSharedKeyUpdate(string SharedKey, string SharedGroupId);

public sealed class SettingsState : INotifyPropertyChanged
{
    private bool sharedKeyConfigured;
    private bool sharingEnabled;
    private bool startupEnabled;
    private string sharedGroupId = string.Empty;
    private string sharedKeyInput = string.Empty;
    private string sharedKeyConfirmationInput = string.Empty;
    private string lastStatusMessage;
    private RemoteFileOfferSummary? remoteFileOffer;
    private readonly Dictionary<string, string> pendingPeers = new();
    private readonly HashSet<string> trustedPeerIds = new(StringComparer.Ordinal);
    private readonly Dictionary<string, ConnectedPeerSummary> connectedPeers = new(StringComparer.Ordinal);
    private ConnectedPeerSummary? localDevice;
    private int connectedPeerCount;
    private IReadOnlyList<ConnectedPeerSummary> connectedRemotePeerSummaries = Array.Empty<ConnectedPeerSummary>();
    private IReadOnlyList<ConnectedPeerSummary> connectedPeerSummaries = Array.Empty<ConnectedPeerSummary>();
    private string connectedPeersTooltip = "暂无连接设备";

    private static readonly TimeSpan ConnectedPeerTimeout = TimeSpan.FromSeconds(15);

    public SettingsState(
        bool sharedKeyConfigured,
        bool sharingEnabled,
        bool startupEnabled,
        string sharedGroupId = "",
        string sharedKeyInput = "")
    {
        this.sharedKeyConfigured = sharedKeyConfigured;
        this.sharingEnabled = sharingEnabled;
        this.startupEnabled = startupEnabled;
        this.sharedGroupId = sharedGroupId;
        this.sharedKeyInput = sharedKeyInput;
        lastStatusMessage = sharedKeyConfigured ? "剪贴板共享准备就绪" : "请先设置共享 Key";
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    public event Action<string>? PeerApproved;
    public event Action<string>? RemoteFileReceiveRequested;

    public bool SharedKeyConfigured
    {
        get => sharedKeyConfigured;
        set
        {
            if (SetField(ref sharedKeyConfigured, value))
            {
                OnPropertyChanged(nameof(RequiresKeySetup));
                OnPropertyChanged(nameof(SharedKeyPlaceholder));
                OnPropertyChanged(nameof(CanPublishClipboardContent));
                RefreshConnectedPeerDisplay(DateTimeOffset.UtcNow);
            }
        }
    }

    public bool SharingEnabled
    {
        get => sharingEnabled;
        set
        {
            if (SetField(ref sharingEnabled, value))
            {
                OnPropertyChanged(nameof(CanPublishClipboardContent));
                RefreshConnectedPeerDisplay(DateTimeOffset.UtcNow);
            }
        }
    }

    public bool StartupEnabled
    {
        get => startupEnabled;
        set => SetField(ref startupEnabled, value);
    }

    public string SharedGroupId
    {
        get => sharedGroupId;
        private set => SetField(ref sharedGroupId, value);
    }

    public string SharedKeyInput
    {
        get => sharedKeyInput;
        set => SetField(ref sharedKeyInput, value);
    }

    public string SharedKeyConfirmationInput
    {
        get => sharedKeyConfirmationInput;
        set => SetField(ref sharedKeyConfirmationInput, value);
    }

    public string LastStatusMessage
    {
        get => lastStatusMessage;
        set => SetField(ref lastStatusMessage, value);
    }

    public RemoteFileOfferSummary? RemoteFileOffer
    {
        get => remoteFileOffer;
        private set
        {
            if (SetField(ref remoteFileOffer, value))
            {
                OnPropertyChanged(nameof(HasRemoteFileOffer));
            }
        }
    }

    public bool RequiresKeySetup => !SharedKeyConfigured;
    public string SharedKeyPlaceholder => SharedKeyConfigured ? "***" : "输入 Key";
    public int PendingPeerCount => pendingPeers.Count;
    public int TrustedPeerCount => trustedPeerIds.Count;
    public bool CanPublishClipboardContent => SharedKeyConfigured && SharingEnabled;
    public bool HasRemoteFileOffer => RemoteFileOffer is not null;
    public int ConnectedPeerCount => connectedPeerCount;

    public IReadOnlyCollection<string> TrustedPeerIds => trustedPeerIds.ToArray();

    public IReadOnlyList<ConnectedPeerSummary> ConnectedRemotePeerSummaries => connectedRemotePeerSummaries;
    public IReadOnlyList<ConnectedPeerSummary> ConnectedPeerSummaries => connectedPeerSummaries;
    public string ConnectedPeersTooltip => connectedPeersTooltip;

    public IReadOnlyList<PendingPeerSummary> PendingPeerSummaries => pendingPeers
        .Select(peer => new PendingPeerSummary(peer.Key, peer.Value))
        .OrderBy(peer => peer.DeviceName, StringComparer.CurrentCultureIgnoreCase)
        .ThenBy(peer => peer.DeviceId, StringComparer.Ordinal)
        .ToArray();

    public static PreparedSharedKeyUpdate PrepareSharedKeyUpdate(string rawKey, string confirmation)
    {
        var normalizedKey = rawKey.Trim();
        var normalizedConfirmation = confirmation.Trim();

        if (string.IsNullOrEmpty(normalizedKey))
        {
            throw new ArgumentException("共享 Key 不能为空", nameof(rawKey));
        }

        if (!string.Equals(normalizedKey, normalizedConfirmation, StringComparison.Ordinal))
        {
            throw new ArgumentException("两次输入的共享 Key 不一致", nameof(confirmation));
        }

        return new PreparedSharedKeyUpdate(normalizedKey, SharedKeyHasher.GroupIdFor(normalizedKey));
    }

    public void UpdateSharedKey(string rawKey, string confirmation)
    {
        ApplySharedKeyUpdate(PrepareSharedKeyUpdate(rawKey, confirmation));
    }

    public void ApplySharedKeyUpdate(PreparedSharedKeyUpdate update)
    {
        SharedKeyInput = update.SharedKey;
        SharedGroupId = update.SharedGroupId;
        SharedKeyConfigured = true;
        SharedKeyConfirmationInput = string.Empty;
        LastStatusMessage = "共享 Key 已设置";
    }

    public void MarkPeerPending(string deviceId, string deviceName)
    {
        if (string.IsNullOrEmpty(deviceId) || trustedPeerIds.Contains(deviceId))
        {
            return;
        }

        pendingPeers[deviceId] = string.IsNullOrEmpty(deviceName) ? deviceId : deviceName;
        LastStatusMessage = $"发现 {pendingPeers.Count} 台待确认设备";
        OnPropertyChanged(nameof(PendingPeerCount));
        OnPropertyChanged(nameof(PendingPeerSummaries));
    }

    public void ApprovePendingPeers()
    {
        var approvedDeviceIds = pendingPeers.Keys.ToArray();
        foreach (var deviceId in approvedDeviceIds)
        {
            trustedPeerIds.Add(deviceId);
        }

        pendingPeers.Clear();
        LastStatusMessage = "待确认设备已允许";
        OnPropertyChanged(nameof(PendingPeerCount));
        OnPropertyChanged(nameof(PendingPeerSummaries));
        OnPropertyChanged(nameof(TrustedPeerCount));
        OnPropertyChanged(nameof(CanPublishClipboardContent));

        foreach (var deviceId in approvedDeviceIds)
        {
            PeerApproved?.Invoke(deviceId);
        }
    }

    public void ApprovePendingPeer(string deviceId)
    {
        if (!pendingPeers.Remove(deviceId))
        {
            return;
        }

        trustedPeerIds.Add(deviceId);
        LastStatusMessage = pendingPeers.Count == 0
            ? "设备已允许"
            : $"设备已允许，仍有 {pendingPeers.Count} 台待确认设备";
        OnPropertyChanged(nameof(PendingPeerCount));
        OnPropertyChanged(nameof(PendingPeerSummaries));
        OnPropertyChanged(nameof(TrustedPeerCount));
        OnPropertyChanged(nameof(CanPublishClipboardContent));
        PeerApproved?.Invoke(deviceId);
    }

    public bool TrustPeer(string deviceId, string deviceName)
    {
        if (string.IsNullOrEmpty(deviceId))
        {
            return false;
        }

        if (trustedPeerIds.Contains(deviceId))
        {
            return false;
        }

        pendingPeers.Remove(deviceId);
        trustedPeerIds.Add(deviceId);
        LastStatusMessage = $"设备 {(string.IsNullOrEmpty(deviceName) ? deviceId : deviceName)} 已信任";
        OnPropertyChanged(nameof(PendingPeerCount));
        OnPropertyChanged(nameof(PendingPeerSummaries));
        OnPropertyChanged(nameof(TrustedPeerCount));
        OnPropertyChanged(nameof(CanPublishClipboardContent));
        return true;
    }

    public bool IsPeerTrusted(string deviceId)
    {
        return trustedPeerIds.Contains(deviceId);
    }

    public void RecordConnectedPeer(
        string deviceId,
        string deviceName,
        string ipAddress,
        DateTimeOffset? now = null)
    {
        var normalizedDeviceId = deviceId.Trim();
        if (string.IsNullOrEmpty(normalizedDeviceId))
        {
            return;
        }

        var referenceTime = now ?? DateTimeOffset.UtcNow;
        var normalizedDeviceName = string.IsNullOrWhiteSpace(deviceName)
            ? normalizedDeviceId
            : deviceName.Trim();
        var normalizedIpAddress = string.IsNullOrWhiteSpace(ipAddress)
            ? "未知 IP"
            : ipAddress.Trim();

        connectedPeers[normalizedDeviceId] = new ConnectedPeerSummary(
            normalizedDeviceId,
            normalizedDeviceName,
            normalizedIpAddress,
            referenceTime
        );
        RemoveExpiredConnectedPeers(referenceTime);
        RefreshConnectedPeerDisplay(referenceTime);
    }

    public void SetLocalDevice(
        string deviceId,
        string deviceName,
        string ipAddress)
    {
        var normalizedDeviceId = deviceId.Trim();
        if (string.IsNullOrEmpty(normalizedDeviceId))
        {
            return;
        }

        localDevice = new ConnectedPeerSummary(
            normalizedDeviceId,
            string.IsNullOrWhiteSpace(deviceName) ? normalizedDeviceId : deviceName.Trim(),
            string.IsNullOrWhiteSpace(ipAddress) ? "未知 IP" : ipAddress.Trim(),
            DateTimeOffset.UtcNow
        );
        RefreshConnectedPeerDisplay(DateTimeOffset.UtcNow);
    }

    public void PurgeExpiredConnectedPeers(DateTimeOffset? now = null)
    {
        var referenceTime = now ?? DateTimeOffset.UtcNow;
        if (RemoveExpiredConnectedPeers(referenceTime))
        {
            RefreshConnectedPeerDisplay(referenceTime);
        }
    }

    public void UpdateRemoteFileOffer(RemoteFileOfferSummary offer, bool autoRequestReceive = true)
    {
        RemoteFileOffer = offer;
        LastStatusMessage = offer.DisplayTitle;
        if (autoRequestReceive)
        {
            RequestRemoteFileReceive();
        }
    }

    public void ClearRemoteFileOffer(string transferId)
    {
        if (!string.Equals(RemoteFileOffer?.TransferId, transferId, StringComparison.Ordinal))
        {
            return;
        }

        RemoteFileOffer = null;
    }

    public void ResetPeerDiscovery()
    {
        pendingPeers.Clear();
        connectedPeers.Clear();
        RemoteFileOffer = null;
        OnPropertyChanged(nameof(PendingPeerCount));
        OnPropertyChanged(nameof(PendingPeerSummaries));
        RefreshConnectedPeerDisplay(DateTimeOffset.UtcNow);
    }

    public void RequestRemoteFileReceive()
    {
        if (RemoteFileOffer is null)
        {
            return;
        }

        RemoteFileReceiveRequested?.Invoke(RemoteFileOffer.TransferId);
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return false;
        }

        field = value;
        OnPropertyChanged(propertyName);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private bool RemoveExpiredConnectedPeers(DateTimeOffset now)
    {
        var expiredDeviceIds = connectedPeers
            .Where(peer => IsConnectedPeerExpired(peer.Value.LastSeen, now))
            .Select(peer => peer.Key)
            .ToArray();
        foreach (var deviceId in expiredDeviceIds)
        {
            connectedPeers.Remove(deviceId);
        }

        return expiredDeviceIds.Length > 0;
    }

    private void OnConnectedPeersChanged()
    {
        OnPropertyChanged(nameof(ConnectedPeerCount));
        OnPropertyChanged(nameof(ConnectedPeerSummaries));
        OnPropertyChanged(nameof(ConnectedRemotePeerSummaries));
        OnPropertyChanged(nameof(ConnectedPeersTooltip));
    }

    private void RefreshConnectedPeerDisplay(DateTimeOffset now)
    {
        connectedRemotePeerSummaries = connectedPeers.Values
            .Where(peer => !IsConnectedPeerExpired(peer.LastSeen, now))
            .OrderBy(peer => peer.DeviceName, StringComparer.CurrentCultureIgnoreCase)
            .ThenBy(peer => peer.IpAddress, StringComparer.Ordinal)
            .ThenBy(peer => peer.DeviceId, StringComparer.Ordinal)
            .ToArray();
        var displayRemotePeers = connectedRemotePeerSummaries
            .Where(peer => !string.Equals(peer.DeviceId, localDevice?.DeviceId, StringComparison.Ordinal))
            .ToArray();
        connectedPeerSummaries = CanPublishClipboardContent && localDevice is not null
            ? new[] { localDevice }.Concat(displayRemotePeers).ToArray()
            : displayRemotePeers;
        connectedPeerCount = connectedPeerSummaries.Count;
        connectedPeersTooltip = ConnectedPeersTooltipFor(
            connectedPeerSummaries,
            CanPublishClipboardContent ? localDevice?.DeviceId : null
        );
        OnConnectedPeersChanged();
    }

    private static string ConnectedPeersTooltipFor(
        IReadOnlyList<ConnectedPeerSummary> summaries,
        string? localDeviceId)
    {
        return summaries.Count == 0
            ? "暂无连接设备"
            : string.Join(
                $"{Environment.NewLine}{Environment.NewLine}",
                summaries.Select(peer =>
                {
                    var localMarker = string.Equals(peer.DeviceId, localDeviceId, StringComparison.Ordinal)
                        ? "（本机）"
                        : string.Empty;
                    return $"机器名：{peer.DeviceName}{localMarker}{Environment.NewLine}IP：{peer.IpAddress}";
                })
            );
    }

    private static bool IsConnectedPeerExpired(DateTimeOffset lastSeen, DateTimeOffset now)
    {
        return now - lastSeen > ConnectedPeerTimeout;
    }
}

public sealed record PendingPeerSummary(string DeviceId, string DeviceName)
{
    public string ShortDeviceId => DeviceId.Length <= 8 ? DeviceId : DeviceId[..8];
}

public sealed record ConnectedPeerSummary(
    string DeviceId,
    string DeviceName,
    string IpAddress,
    DateTimeOffset LastSeen);

public sealed record RemoteFileOfferSummary(
    string TransferId,
    string SourceDeviceId,
    string SourceDeviceName,
    string SourceHost,
    int FileCount,
    long TotalBytes,
    int ClipboardGeneration = 0)
{
    public string DisplayTitle => $"{SourceDeviceName}：{FileCount} 个文件可接收";
}
