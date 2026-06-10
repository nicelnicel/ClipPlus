using System.IO.Compression;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Startup;
using ClipPlus.Windows.Diagnostics;
using Xunit;

namespace ClipPlus.Windows.Tests;

public sealed class SettingsStateTests
{
    [Fact]
    public void MissingKeyRequiresSetup()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.True(state.RequiresKeySetup);
    }

    [Fact]
    public void StartupToggleUpdatesState()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.StartupEnabled = true;

        Assert.True(state.StartupEnabled);
    }

    [Fact]
    public void SharedKeyStoresOnlyDerivedGroupIdentifier()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.UpdateSharedKey("clipplus-test-key", "clipplus-test-key");

        Assert.True(state.SharedKeyConfigured);
        Assert.Equal("OcePlqBkjK6NLJjtPRglTw", state.SharedGroupId);
        Assert.DoesNotContain("clipplus-test-key", state.SharedGroupId);
    }

    [Fact]
    public void MismatchedSharedKeyConfirmationFails()
    {
        var state = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.Throws<ArgumentException>(() => state.UpdateSharedKey("clipplus-test-key", "other-key"));
        Assert.False(state.SharedKeyConfigured);
        Assert.True(state.RequiresKeySetup);
    }

    [Fact]
    public void PendingPeerMustBeApprovedBeforeSync()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.MarkPeerPending("mac-device", "MacBook");

        Assert.Equal(1, state.PendingPeerCount);
        Assert.False(state.IsPeerTrusted("mac-device"));

        state.ApprovePendingPeers();

        Assert.Equal(0, state.PendingPeerCount);
        Assert.True(state.IsPeerTrusted("mac-device"));
    }

    [Fact]
    public void PendingPeerDoesNotAllowPublishingClipboardContentUntilApproved()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.MarkPeerPending("mac-device", "MacBook");

        Assert.False(state.CanPublishClipboardContent);

        state.ApprovePendingPeer("mac-device");

        Assert.True(state.CanPublishClipboardContent);
        Assert.Equal(1, state.TrustedPeerCount);
    }

    [Fact]
    public void PendingPeerSummariesAreSortedAndAllowSingleApproval()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.MarkPeerPending("z-device", "Windows");
        state.MarkPeerPending("a-device", "MacBook");

        Assert.Equal(new[] { "MacBook", "Windows" }, state.PendingPeerSummaries.Select(peer => peer.DeviceName));

        state.ApprovePendingPeer("a-device");

        Assert.Equal(1, state.PendingPeerCount);
        Assert.True(state.IsPeerTrusted("a-device"));
        Assert.False(state.IsPeerTrusted("z-device"));
    }

    [Fact]
    public void RepeatedTrustForAlreadyTrustedPeerDoesNotRewriteStatus()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.True(state.TrustPeer("mac-device", "MacBook"));
        state.LastStatusMessage = "稳定状态";

        Assert.False(state.TrustPeer("mac-device", "MacBook"));

        Assert.Equal(1, state.TrustedPeerCount);
        Assert.Equal("稳定状态", state.LastStatusMessage);
    }

    [Fact]
    public void ClipPlusMessageRoundTripsTextPayload()
    {
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateText(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            text: "hello from windows"
        );

        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Text, decoded.Kind);
        Assert.Equal(1, decoded.ProtocolVersion);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("hello from windows", decoded.Text);
    }

    [Fact]
    public void ClipPlusMessageRoundTripsInlinePngImagePayload()
    {
        var pngData = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateImage(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            pngData: pngData
        );

        Assert.NotNull(message);
        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Image, decoded.Kind);
        Assert.Equal(1, decoded.ProtocolVersion);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal(pngData.Length, decoded.ImageByteSize);
        Assert.Equal(Convert.ToBase64String(pngData), decoded.ImageBase64);
        Assert.Equal(pngData, decoded.DecodedImageData);
        Assert.False(string.IsNullOrEmpty(decoded.ImageContentHash));
    }

    [Fact]
    public void ClipPlusMessageRoundTripsTrustPayload()
    {
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateTrust(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            approvedDeviceId: "mac-device"
        );

        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Trust, decoded.Kind);
        Assert.Equal(1, decoded.ProtocolVersion);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("mac-device", decoded.ApprovedDeviceId);
    }

    [Fact]
    public void ClipPlusMessageRejectsOversizedInlineImagePayload()
    {
        var pngData = Enumerable.Repeat((byte)0xFF, ClipPlus.Windows.Sync.ClipPlusMessage.MaxInlineImageBytes + 1)
            .ToArray();

        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateImage(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            pngData: pngData
        );

        Assert.Null(message);
    }

    [Fact]
    public void StartupManagerReportsEnabledWhenRunEntryMatchesExecutable()
    {
        var store = new FakeStartupEntryStore();
        var manager = new StartupManager(store, @"C:\ClipPlus\ClipPlus.Windows.exe");
        store.Value = "\"C:\\ClipPlus\\ClipPlus.Windows.exe\"";

        Assert.True(manager.IsEnabled());
    }

    [Fact]
    public void StartupManagerWritesQuotedExecutablePathWhenEnabled()
    {
        var store = new FakeStartupEntryStore();
        var manager = new StartupManager(store, @"C:\ClipPlus\ClipPlus.Windows.exe");

        manager.SetEnabled(true);

        Assert.Equal("ClipPlus", store.Name);
        Assert.Equal("\"C:\\ClipPlus\\ClipPlus.Windows.exe\"", store.Value);
    }

    [Fact]
    public void StartupManagerDeletesRunEntryWhenDisabled()
    {
        var store = new FakeStartupEntryStore
        {
            Value = "\"C:\\ClipPlus\\ClipPlus.Windows.exe\""
        };
        var manager = new StartupManager(store, @"C:\ClipPlus\ClipPlus.Windows.exe");

        manager.SetEnabled(false);

        Assert.Equal("ClipPlus", store.DeletedName);
        Assert.Null(store.Value);
    }

    [Fact]
    public void DiagnosticsExporterWritesRedactedStatusAndLogZip()
    {
        var directory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(directory);
        var logPath = Path.Combine(directory, "clipplus.log");
        File.WriteAllText(logPath, "raw key clipplus-test-key clipboard secret-value");
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );
        state.UpdateSharedKey("another-key", "another-key");
        state.MarkPeerPending("mac-device", "Mac");
        var exporter = new DiagnosticsExporter(
            logPath,
            directory,
            new[] { "clipplus-test-key", "secret-value" }
        );

        var exportPath = exporter.Export(state);
        using var archive = ZipFile.OpenRead(exportPath);
        var status = ReadZipEntry(archive, "status.json");
        var log = ReadZipEntry(archive, "clipplus.log");

        Assert.EndsWith(".zip", exportPath);
        Assert.Contains("shared_key_configured", status);
        Assert.Contains("pending_peer_count", status);
        Assert.DoesNotContain("clipplus-test-key", status);
        Assert.DoesNotContain("clipplus-test-key", log);
        Assert.DoesNotContain("secret-value", log);
        Assert.Contains("<redacted>", log);
    }

    private static string ReadZipEntry(ZipArchive archive, string entryName)
    {
        var entry = archive.GetEntry(entryName);
        Assert.NotNull(entry);
        using var reader = new StreamReader(entry.Open());
        return reader.ReadToEnd();
    }
}

internal sealed class FakeStartupEntryStore : IStartupEntryStore
{
    public string? Name { get; private set; }
    public string? Value { get; set; }
    public string? DeletedName { get; private set; }

    public string? ReadValue(string name)
    {
        Name = name;
        return Value;
    }

    public void SetValue(string name, string value)
    {
        Name = name;
        Value = value;
    }

    public void DeleteValue(string name)
    {
        DeletedName = name;
        Value = null;
    }
}
