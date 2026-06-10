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
        Assert.Equal(ExpectedGroupId("clipplus-test-key"), state.SharedGroupId);
        Assert.DoesNotContain("clipplus-test-key", state.SharedGroupId);
    }

    [Fact]
    public void CoreBridgeDerivesGroupIdWhenFfiLibraryIsAvailable()
    {
        var ffiLibraryPath = Environment.GetEnvironmentVariable("CLIPPLUS_FFI_LIBRARY_PATH");
        var groupId = new ClipPlus.Windows.CoreBridge.CoreBridge().DeriveGroupId("clipplus-test-key");
        if (groupId is null)
        {
            if (!string.IsNullOrWhiteSpace(ffiLibraryPath))
            {
                Assert.Fail($"Expected CoreBridge to load FFI library from CLIPPLUS_FFI_LIBRARY_PATH: {ffiLibraryPath}");
            }

            return;
        }

        Assert.Equal("21YR2N3_wcdRPmEMLiuLMA", groupId);
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
    public void ClipPlusMessageRoundTripsFileOfferPayloadWithoutLocalPaths()
    {
        var item = new ClipPlus.Windows.Sync.FileTransferItem(
            RelativePath: @"Reports/Q1.txt",
            ByteSize: 12,
            IsDirectory: false
        );
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateFileOffer(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            transferId: "transfer-1",
            files: new[] { item },
            archivePort: 47_632
        );

        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.FileOffer, decoded.Kind);
        Assert.Equal("transfer-1", decoded.TransferId);
        Assert.Equal(47_632, decoded.ArchivePort);
        Assert.Equal(new[] { item }, decoded.Files);
        Assert.DoesNotContain(@"C:\\", json);
        Assert.DoesNotContain("/Users/", json);
    }

    [Fact]
    public void RemoteFileOfferCanRequestReceive()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );
        string? requestedTransferId = null;
        state.RemoteFileReceiveRequested += transferId => requestedTransferId = transferId;

        state.UpdateRemoteFileOffer(new RemoteFileOfferSummary(
            TransferId: "transfer-1",
            SourceDeviceId: "mac-device",
            SourceDeviceName: "Mac",
            SourceHost: "10.211.55.2",
            FileCount: 2,
            TotalBytes: 24
        ));

        Assert.Equal("Mac：2 个文件可接收", state.RemoteFileOffer?.DisplayTitle);
        Assert.True(state.HasRemoteFileOffer);

        state.RequestRemoteFileReceive();

        Assert.Equal("transfer-1", requestedTransferId);
    }

    [Fact]
    public void FileTransferArchiveWritesZipEntriesForFilesAndDirectories()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var sourceDirectory = Path.Combine(temporaryDirectory, "source");
        var nestedDirectory = Path.Combine(sourceDirectory, "Nested");
        Directory.CreateDirectory(nestedDirectory);
        File.WriteAllText(Path.Combine(sourceDirectory, "a.txt"), "alpha");
        File.WriteAllText(Path.Combine(nestedDirectory, "b.txt"), "beta");
        var archivePath = Path.Combine(temporaryDirectory, "files.zip");

        ClipPlus.Windows.Sync.FileTransferArchive.WriteZip(
            new[] { Path.Combine(sourceDirectory, "a.txt"), nestedDirectory },
            archivePath
        );

        var extractedDirectory = Path.Combine(temporaryDirectory, "unzipped");
        ZipFile.ExtractToDirectory(archivePath, extractedDirectory);

        Assert.Equal("alpha", File.ReadAllText(Path.Combine(extractedDirectory, "a.txt")));
        Assert.Equal("beta", File.ReadAllText(Path.Combine(extractedDirectory, "Nested", "b.txt")));
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
    public void StartupManagerWritesAndDeletesRealRunEntryWhenExplicitlyEnabled()
    {
        if (Environment.GetEnvironmentVariable("CLIPPLUS_ENABLE_SYSTEM_STARTUP_TEST") != "1")
        {
            return;
        }

        const string entryName = "ClipPlus";
        var store = new RegistryStartupEntryStore();
        var originalValue = store.ReadValue(entryName);
        var executablePath = ResolveStartupExecutablePath();
        Assert.True(File.Exists(executablePath), $"Startup executable does not exist: {executablePath}");
        var manager = new StartupManager(store, executablePath);

        try
        {
            manager.SetEnabled(true);

            Assert.Equal($"\"{executablePath}\"", store.ReadValue(entryName));
            Assert.True(manager.IsEnabled());

            manager.SetEnabled(false);

            Assert.Null(store.ReadValue(entryName));
            Assert.False(manager.IsEnabled());
        }
        finally
        {
            if (originalValue is null)
            {
                store.DeleteValue(entryName);
            }
            else
            {
                store.SetValue(entryName, originalValue);
            }
        }
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

    private static string ResolveStartupExecutablePath()
    {
        var configuredPath = Environment.GetEnvironmentVariable("CLIPPLUS_SYSTEM_STARTUP_EXE");
        if (!string.IsNullOrWhiteSpace(configuredPath))
        {
            return configuredPath;
        }

        return Path.GetFullPath(Path.Combine(
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            "ClipPlus.Windows",
            "bin",
            "Debug",
            "net8.0-windows",
            "ClipPlus.Windows.exe"
        ));
    }

    private static string ExpectedGroupId(string rawKey)
    {
        return new ClipPlus.Windows.CoreBridge.CoreBridge().DeriveGroupId(rawKey) ?? "OcePlqBkjK6NLJjtPRglTw";
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
