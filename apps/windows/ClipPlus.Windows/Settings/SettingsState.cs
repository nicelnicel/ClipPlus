using System.ComponentModel;
using System.Runtime.CompilerServices;
using ClipPlus.Windows.Sync;

namespace ClipPlus.Windows.Settings;

public sealed class SettingsState : INotifyPropertyChanged
{
    private bool sharedKeyConfigured;
    private bool sharingEnabled;
    private bool startupEnabled;
    private string sharedGroupId = string.Empty;
    private string sharedKeyInput = string.Empty;
    private string sharedKeyConfirmationInput = string.Empty;
    private string lastStatusMessage;
    private readonly Dictionary<string, string> pendingPeers = new();
    private readonly HashSet<string> trustedPeerIds = new(StringComparer.Ordinal);

    public SettingsState(bool sharedKeyConfigured, bool sharingEnabled, bool startupEnabled)
    {
        this.sharedKeyConfigured = sharedKeyConfigured;
        this.sharingEnabled = sharingEnabled;
        this.startupEnabled = startupEnabled;
        lastStatusMessage = sharedKeyConfigured ? "剪贴板共享准备就绪" : "请先设置共享 Key";
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool SharedKeyConfigured
    {
        get => sharedKeyConfigured;
        set => SetField(ref sharedKeyConfigured, value);
    }

    public bool SharingEnabled
    {
        get => sharingEnabled;
        set => SetField(ref sharingEnabled, value);
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

    public bool RequiresKeySetup => !SharedKeyConfigured;
    public int PendingPeerCount => pendingPeers.Count;

    public void UpdateSharedKey(string rawKey, string confirmation)
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

        SharedGroupId = SharedKeyHasher.GroupIdFor(normalizedKey);
        SharedKeyConfigured = true;
        SharedKeyInput = string.Empty;
        SharedKeyConfirmationInput = string.Empty;
        LastStatusMessage = "共享 Key 已设置";
        OnPropertyChanged(nameof(RequiresKeySetup));
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
    }

    public void ApprovePendingPeers()
    {
        foreach (var deviceId in pendingPeers.Keys)
        {
            trustedPeerIds.Add(deviceId);
        }

        pendingPeers.Clear();
        LastStatusMessage = "待确认设备已允许";
        OnPropertyChanged(nameof(PendingPeerCount));
    }

    public bool IsPeerTrusted(string deviceId)
    {
        return trustedPeerIds.Contains(deviceId);
    }

    private void SetField<T>(ref T field, T value, [CallerMemberName] string? propertyName = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        OnPropertyChanged(propertyName);
    }

    private void OnPropertyChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }
}
