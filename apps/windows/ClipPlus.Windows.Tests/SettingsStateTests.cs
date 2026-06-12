using System.Buffers.Binary;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
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
    public void ConfiguredSharedKeyCanLoadStoredRawKeyForEyeReveal()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false,
            sharedGroupId: "stored-group",
            sharedKeyInput: "clipplus-test-key"
        );

        Assert.Equal("***", state.SharedKeyPlaceholder);
        Assert.Equal("clipplus-test-key", state.SharedKeyInput);

        state.UpdateSharedKey("clipplus-test-key", "clipplus-test-key");

        Assert.Equal("***", state.SharedKeyPlaceholder);
        Assert.Equal("clipplus-test-key", state.SharedKeyInput);
        Assert.DoesNotContain("clipplus-test-key", state.SharedGroupId);
    }

    [Fact]
    public void AppOpensSettingsWhenKeySetupIsRequiredOrE2ERequestsIt()
    {
        var missingKeyState = new SettingsState(
            sharedKeyConfigured: false,
            sharingEnabled: true,
            startupEnabled: false
        );
        var configuredState = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        Assert.Equal("输入 Key", missingKeyState.SharedKeyPlaceholder);
        Assert.True(ClipPlus.Windows.App.ShouldOpenSettingsWindow(missingKeyState, showSettingsRequested: false));
        Assert.True(ClipPlus.Windows.App.ShouldOpenSettingsWindow(configuredState, showSettingsRequested: true));
        Assert.False(ClipPlus.Windows.App.ShouldOpenSettingsWindow(configuredState, showSettingsRequested: false));
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
    public void SettingsStorePersistsInstallSafeConfiguration()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusTests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            var store = new SettingsStore(directory);

            Assert.Equal(
                new PersistedSettings(
                    SharedKeyConfigured: false,
                    SharingEnabled: true,
                    SharedGroupId: string.Empty
                ),
                store.Load()
            );

            store.Save(new PersistedSettings(
                SharedKeyConfigured: true,
                SharingEnabled: false,
                SharedGroupId: "group-id"
            )
            {
                SharedKeyInput = "clipplus-test-key"
            });

            Assert.Equal(
                new PersistedSettings(
                    SharedKeyConfigured: true,
                    SharingEnabled: false,
                    SharedGroupId: "group-id"
                )
                {
                    SharedKeyInput = "clipplus-test-key"
                },
                new SettingsStore(directory).Load()
            );

            var settingsJson = File.ReadAllText(Path.Combine(directory, "settings.json"));
            Assert.DoesNotContain("clipplus-test-key", settingsJson);
            Assert.Equal(
                "clipplus-test-key",
                File.ReadAllText(Path.Combine(directory, "clipplus.shared-key")).Trim()
            );
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void StoredGroupIdWithoutPlainTextKeyRequiresSetupAgain()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusTests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            File.WriteAllText(
                Path.Combine(directory, "settings.json"),
                """{"SharedKeyConfigured":true,"SharingEnabled":true,"SharedGroupId":"legacy-group-id"}"""
            );

            Assert.Equal(
                new PersistedSettings(
                    SharedKeyConfigured: false,
                    SharingEnabled: true,
                    SharedGroupId: "legacy-group-id"
                ),
                new SettingsStore(directory).Load()
            );
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void SettingsStoreSaveStatePersistsPlainTextKeyForEyeRevealAfterRestart()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusTests-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        try
        {
            var state = new SettingsState(
                sharedKeyConfigured: false,
                sharingEnabled: true,
                startupEnabled: false
            );
            state.UpdateSharedKey("clipplus-test-key", "clipplus-test-key");

            new SettingsStore(directory).Save(state);

            Assert.Equal(
                new PersistedSettings(
                    SharedKeyConfigured: true,
                    SharingEnabled: true,
                    SharedGroupId: ExpectedGroupId("clipplus-test-key")
                )
                {
                    SharedKeyInput = "clipplus-test-key"
                },
                new SettingsStore(directory).Load()
            );
            Assert.Equal(
                "clipplus-test-key",
                File.ReadAllText(Path.Combine(directory, "clipplus.shared-key")).Trim()
            );
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void SettingsUiOnlyShowsKeySharingAndStartupControls()
    {
        var repositoryRoot = FindRepositoryRoot();
        var settingsXaml = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Settings",
            "SettingsWindow.xaml"
        ));
        var traySource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Tray",
            "TrayController.cs"
        ));
        var settingsCode = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Settings",
            "SettingsWindow.xaml.cs"
        ));
        var syncSource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Sync",
            "UdpTextSyncService.cs"
        ));
        var settingsStateSource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Settings",
            "SettingsState.cs"
        ));
        Assert.Contains("共享 Key", settingsXaml);
        Assert.Contains("SizeToContent=\"Height\"", settingsXaml);
        Assert.DoesNotContain("Height=\"255\"", settingsXaml);
        Assert.DoesNotContain("Height=\"210\"", settingsXaml);
        Assert.Contains("开启局域网剪贴板", settingsXaml);
        Assert.Contains("开机启动", settingsXaml);
        Assert.Contains("by.YJY_hi", settingsXaml);
        Assert.Contains("RequestNavigate=\"AuthorLink_RequestNavigate\"", settingsXaml);
        Assert.Contains("NavigateUri=\"https://github.com/nicelnicel\"", settingsXaml);
        Assert.Contains("HorizontalAlignment=\"Right\"", settingsXaml);
        Assert.Contains("退出 ClipPlus", settingsXaml);
        Assert.Contains("Click=\"Exit_Click\"", settingsXaml);
        Assert.True(
            settingsXaml.IndexOf("by.YJY_hi", StringComparison.Ordinal)
                < settingsXaml.IndexOf("退出 ClipPlus", StringComparison.Ordinal),
            "作者链接应该放在退出按钮上一行"
        );
        Assert.Contains("ToggleKeyVisibility", settingsXaml);
        Assert.Contains("SharedKeyPasswordBox", settingsXaml);
        Assert.Contains("SharedKeyTextBox", settingsXaml);
        Assert.Contains("SharedKeyInput_LostFocus", settingsXaml);
        Assert.Contains("SharedKeyInputBorder", settingsXaml);
        Assert.Contains("Text=\"输入 Key\"", settingsXaml);
        Assert.DoesNotContain("Text=\"{Binding SharedKeyPlaceholder}\"", settingsXaml);
        Assert.Contains("!state.SharedKeyConfigured", settingsCode);
        Assert.Contains("BorderThickness=\"1\"", settingsXaml);
        Assert.Contains("BorderThickness=\"0\"", settingsXaml);
        Assert.Contains("Segoe MDL2 Assets", settingsXaml);
        Assert.DoesNotContain("保存 Key", settingsXaml);
        Assert.DoesNotContain("请先设置共享 Key", settingsXaml);

        var disallowedVisibleLabels = new[]
        {
            "状态",
            "LastStatusMessage",
            "导出诊断包",
            "待确认设备",
            "允许",
            "可接收文件",
            "暂无可接收文件",
            "再次输入共享 Key",
            "开始局域网剪贴板",
            "作者 YJY"
        };

        foreach (var label in disallowedVisibleLabels)
        {
            Assert.DoesNotContain(label, settingsXaml);
            Assert.DoesNotContain(label, traySource);
        }

        Assert.DoesNotContain("ApprovePending", settingsXaml);
        Assert.DoesNotContain("ReceiveRemoteFiles", settingsXaml);
        Assert.DoesNotContain("ExportDiagnostics", settingsXaml);
        Assert.DoesNotContain("state.IsPeerTrusted(message.SenderDeviceId)", syncSource);
        Assert.Contains("ConnectedPeerCount", settingsXaml);
        Assert.Contains("ConnectedPeersTooltip", settingsXaml);
        Assert.Contains("private int connectedPeerCount;", settingsStateSource);
        Assert.Contains("private string connectedPeersTooltip", settingsStateSource);
        Assert.Contains("x:Name=\"ConnectedPeerCountText\"", settingsXaml);
        Assert.Contains("Foreground=\"#0067C0\"", settingsXaml);
        Assert.Contains("<Popup x:Name=\"ConnectedPeersInfoPopup\"", settingsXaml);
        Assert.Contains("PlacementTarget=\"{Binding ElementName=ConnectedPeerCountText}\"", settingsXaml);
        Assert.Contains("IsOpen=\"{Binding IsMouseOver, ElementName=ConnectedPeerCountText, Mode=OneWay}\"", settingsXaml);
        Assert.Contains("Text=\"{Binding ConnectedPeersTooltip}\"", settingsXaml);
        Assert.DoesNotContain(
            "public string ConnectedPeersTooltip\r\n    {\r\n        get",
            settingsStateSource
        );
        Assert.Contains("Task.Run(LocalIPv4Address)", syncSource);
        Assert.Contains("state.SetLocalDevice", syncSource);
        Assert.Contains("Text=\"{Binding ConnectedPeerCount, StringFormat= ({0})}\"", settingsXaml);
        Assert.DoesNotContain("ToolTip=\"{Binding ConnectedPeersTooltip}\"", settingsXaml);
        Assert.DoesNotContain(
            "CheckBox IsChecked=\"{Binding SharingEnabled}\"\r\n                  Margin=\"0,12,0,0\"\r\n                  ToolTip=\"{Binding ConnectedPeersTooltip}\"",
            settingsXaml
        );
        Assert.Contains("RecordConnectedPeer", syncSource);
        Assert.Contains("state.ConnectedRemotePeerSummaries", syncSource);
    }

    [Fact]
    public void TrayControllerReusesSingleSettingsWindow()
    {
        var repositoryRoot = FindRepositoryRoot();
        var traySource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Tray",
            "TrayController.cs"
        ));
        var appSource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "App.xaml.cs"
        ));

        Assert.Contains("private SettingsWindow? settingsWindow;", traySource);
        Assert.Contains("notifyIcon.MouseClick", traySource);
        Assert.Contains("MouseButtons.Left", traySource);
        Assert.Contains("settingsWindow is null", traySource);
        Assert.Contains("settingsWindow.Closed +=", traySource);
        Assert.Contains("settingsWindow = null", traySource);
        Assert.Contains("settingsWindow.Activate()", traySource);
        Assert.DoesNotContain("new SettingsWindow(settingsState).Show();", traySource);
        Assert.Contains("public void ShowSettingsWindow()", traySource);
        Assert.Contains("trayController.ShowSettingsWindow();", appSource);
        Assert.DoesNotContain("new SettingsWindow(settings).Show();", appSource);
    }

    [Fact]
    public void WindowsAppIconIsConfiguredForSingleExePublishing()
    {
        var repositoryRoot = FindRepositoryRoot();
        var iconPath = Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Resources",
            "ClipPlus.ico"
        );
        var projectPath = Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "ClipPlus.Windows.csproj"
        );
        var publishScriptPath = Path.Combine(
            repositoryRoot,
            "scripts",
            "dev",
            "publish-windows-single-exe.ps1"
        );
        var trayControllerPath = Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Tray",
            "TrayController.cs"
        );

        Assert.True(File.Exists(iconPath), $"Missing Windows icon: {iconPath}");
        var project = File.ReadAllText(projectPath);
        Assert.Contains("<OutputType>WinExe</OutputType>", project);
        Assert.Contains("<UseWPF>true</UseWPF>", project);
        Assert.Contains("<ApplicationIcon>Resources\\ClipPlus.ico</ApplicationIcon>", project);
        Assert.Contains("ExtractAssociatedIcon", File.ReadAllText(trayControllerPath));
        var publishScript = File.ReadAllText(publishScriptPath);
        Assert.Contains("clipplus.shared-key", publishScript);
        Assert.Contains("$preservedSharedKey", publishScript);
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
        var bundledLibraryPath = Path.Combine(AppContext.BaseDirectory, "clipplus_ffi.dll");
        var groupId = new ClipPlus.Windows.CoreBridge.CoreBridge().DeriveGroupId("clipplus-test-key");
        if (groupId is null)
        {
            if (!string.IsNullOrWhiteSpace(ffiLibraryPath) || File.Exists(bundledLibraryPath))
            {
                Assert.Fail(
                    $"Expected CoreBridge to load FFI library from CLIPPLUS_FFI_LIBRARY_PATH or app output. " +
                    $"env={ffiLibraryPath ?? "<unset>"} bundled={bundledLibraryPath}"
                );
            }

            return;
        }

        Assert.Equal("21YR2N3_wcdRPmEMLiuLMA", groupId);
    }

    [Fact]
    public void CoreBridgeDerivesGroupIdFromBundledFfiLibrary()
    {
        var bundledLibraryPath = Path.Combine(AppContext.BaseDirectory, "clipplus_ffi.dll");

        Assert.True(
            File.Exists(bundledLibraryPath),
            $"Expected bundled FFI library in test output: {bundledLibraryPath}"
        );
        Assert.Equal(
            "21YR2N3_wcdRPmEMLiuLMA",
            new ClipPlus.Windows.CoreBridge.CoreBridge().DeriveGroupId("clipplus-test-key")
        );
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
    public void ConfiguredKeyAllowsPublishingClipboardContentWithoutPeerApproval()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );

        state.MarkPeerPending("mac-device", "MacBook");

        Assert.True(state.CanPublishClipboardContent);
        Assert.Equal(0, state.TrustedPeerCount);
    }

    [Fact]
    public void ConnectedPeersTrackRecentDevicesForStatusTooltip()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );
        var now = DateTimeOffset.UtcNow;

        state.SetLocalDevice("windows-device", "Windows 11", "10.211.55.3");
        state.RecordConnectedPeer("mac-device", "MacBook", "10.211.55.2", now);

        Assert.Equal(2, state.ConnectedPeerCount);
        Assert.Equal(new[] { "Windows 11", "MacBook" }, state.ConnectedPeerSummaries.Select(peer => peer.DeviceName));
        Assert.Equal(
            $"机器名：Windows 11（本机）{Environment.NewLine}IP：10.211.55.3{Environment.NewLine}{Environment.NewLine}机器名：MacBook{Environment.NewLine}IP：10.211.55.2",
            state.ConnectedPeersTooltip
        );
        Assert.Contains("机器名：", state.ConnectedPeersTooltip);
        Assert.Contains("IP：", state.ConnectedPeersTooltip);

        state.PurgeExpiredConnectedPeers(now.AddSeconds(16));

        Assert.Equal(1, state.ConnectedPeerCount);
        Assert.Equal("Windows 11", Assert.Single(state.ConnectedPeerSummaries).DeviceName);
        Assert.Empty(state.ConnectedRemotePeerSummaries);
        Assert.Equal(
            $"机器名：Windows 11（本机）{Environment.NewLine}IP：10.211.55.3",
            state.ConnectedPeersTooltip
        );
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
    public void CoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable()
    {
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateTextMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            text: "hello from ffi"
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Text, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("Windows", decoded.SenderDeviceName);
        Assert.Equal("hello from ffi", decoded.Text);
    }

    [Fact]
    public void CoreBridgeCreatesHelloMessageJsonWhenFfiLibraryIsAvailable()
    {
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateHelloMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows"
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Hello, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("Windows", decoded.SenderDeviceName);
    }

    [Fact]
    public void CoreBridgeCreatesTrustMessageJsonWhenFfiLibraryIsAvailable()
    {
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateTrustMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            approvedDeviceId: "mac-device"
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Trust, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("mac-device", decoded.ApprovedDeviceId);
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
        Assert.Equal(
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6",
            decoded.ImageContentHash
        );
    }

    [Fact]
    public void CoreBridgeCreatesImageMessageJsonWhenFfiLibraryIsAvailable()
    {
        var pngData = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateImageMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            pngData: pngData
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.Image, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal(pngData.Length, decoded.ImageByteSize);
        Assert.Equal(Convert.ToBase64String(pngData), decoded.ImageBase64);
        Assert.Equal(
            "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6",
            decoded.ImageContentHash
        );
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
    public void CoreBridgeCreatesFileOfferMessageJsonWhenFfiLibraryIsAvailable()
    {
        var item = new ClipPlus.Windows.Sync.FileTransferItem(
            RelativePath: @"Reports/Q1.txt",
            ByteSize: 12,
            IsDirectory: false
        );
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateFileOfferMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            transferId: "transfer-1",
            files: new[] { item },
            archivePort: 47_632
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.FileOffer, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
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
        Assert.Equal("transfer-1", requestedTransferId);

        state.RequestRemoteFileReceive();

        Assert.Equal("transfer-1", requestedTransferId);
    }

    [Fact]
    public void RemoteFileOfferCanAutoRequestReceiveForE2EAutomation()
    {
        var state = new SettingsState(
            sharedKeyConfigured: true,
            sharingEnabled: true,
            startupEnabled: false
        );
        string? requestedTransferId = null;
        state.RemoteFileReceiveRequested += transferId => requestedTransferId = transferId;

        state.UpdateRemoteFileOffer(
            new RemoteFileOfferSummary(
                TransferId: "transfer-auto",
                SourceDeviceId: "mac-device",
                SourceDeviceName: "Mac",
                SourceHost: "10.211.55.2",
                FileCount: 1,
                TotalBytes: 12
            ),
            autoRequestReceive: true
        );

        Assert.Equal("transfer-auto", requestedTransferId);
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
    public void CoreBridgeWritesFileTransferArchiveWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        var sourceDirectory = Path.Combine(temporaryDirectory, "source");
        var nestedDirectory = Path.Combine(sourceDirectory, "Nested");
        Directory.CreateDirectory(nestedDirectory);
        File.WriteAllText(Path.Combine(sourceDirectory, "a.txt"), "alpha");
        File.WriteAllText(Path.Combine(nestedDirectory, "b.txt"), "beta");
        var archivePath = Path.Combine(temporaryDirectory, "core-files.zip");

        Assert.True(new ClipPlus.Windows.CoreBridge.CoreBridge().WriteFileArchiveZip(
            new[] { Path.Combine(sourceDirectory, "a.txt"), nestedDirectory },
            archivePath
        ));

        var extractedDirectory = Path.Combine(temporaryDirectory, "core-unzipped");
        ZipFile.ExtractToDirectory(archivePath, extractedDirectory);

        Assert.Equal("alpha", File.ReadAllText(Path.Combine(extractedDirectory, "a.txt")));
        Assert.Equal("beta", File.ReadAllText(Path.Combine(extractedDirectory, "Nested", "b.txt")));
    }

    [Fact]
    public async Task CoreBridgeServesFileArchiveToSocketWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(temporaryDirectory);
        var sourcePath = Path.Combine(temporaryDirectory, "source.txt");
        File.WriteAllText(sourcePath, "served from windows ffi socket");
        var archivePath = Path.Combine(temporaryDirectory, "served.zip");
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var serverTask = Task.Run(async () =>
        {
            using var client = await listener.AcceptTcpClientAsync();
            var byteCount = new ClipPlus.Windows.CoreBridge.CoreBridge().ServeFileArchiveToSocket(
                client.Client.Handle,
                new[] { sourcePath },
                archivePath);
            Assert.True(byteCount > 0);
        });

        try
        {
            using var receiver = new TcpClient();
            await receiver.ConnectAsync(IPAddress.Loopback, port);
            await using var stream = receiver.GetStream();
            var lengthBytes = new byte[8];
            await stream.ReadExactlyAsync(lengthBytes);
            var byteCount = BinaryPrimitives.ReadUInt64BigEndian(lengthBytes);
            var payload = new byte[byteCount];
            await stream.ReadExactlyAsync(payload);
            await serverTask;

            var receivedPath = Path.Combine(temporaryDirectory, "received.zip");
            await File.WriteAllBytesAsync(receivedPath, payload);
            var extractedDirectory = Path.Combine(temporaryDirectory, "served-unzipped");
            ZipFile.ExtractToDirectory(receivedPath, extractedDirectory);

            Assert.Equal("served from windows ffi socket", File.ReadAllText(Path.Combine(extractedDirectory, "source.txt")));
        }
        finally
        {
            listener.Stop();
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task CoreBridgeFileServerServesRegisteredArchiveWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(temporaryDirectory);
        var sourcePath = Path.Combine(temporaryDirectory, "registered.txt");
        File.WriteAllText(sourcePath, "served from windows ffi file server");
        using var server = new ClipPlus.Windows.CoreBridge.CoreBridge().OpenFileServer(0);
        Assert.NotNull(server);
        Assert.NotEqual(0, server.LocalPort);
        Assert.True(server.RegisterTransfer("transfer-a", new[] { sourcePath }));
        var serverTask = Task.Run(() => server.ServeNext(temporaryDirectory));

        try
        {
            using var receiver = new TcpClient();
            await receiver.ConnectAsync(IPAddress.Loopback, server.LocalPort);
            await using var stream = receiver.GetStream();
            await stream.WriteAsync(Encoding.UTF8.GetBytes("transfer-a\n"));
            var servedByteCount = await serverTask.WaitAsync(TimeSpan.FromSeconds(6));
            Assert.True(servedByteCount > 0);
            var lengthBytes = new byte[8];
            await stream.ReadExactlyAsync(lengthBytes);
            var byteCount = BinaryPrimitives.ReadUInt64BigEndian(lengthBytes);
            var payload = new byte[byteCount];
            await stream.ReadExactlyAsync(payload);

            Assert.Equal(byteCount, servedByteCount);
            var receivedPath = Path.Combine(temporaryDirectory, "file-server-received.zip");
            await File.WriteAllBytesAsync(receivedPath, payload);
            var extractedDirectory = Path.Combine(temporaryDirectory, "file-server-unzipped");
            ZipFile.ExtractToDirectory(receivedPath, extractedDirectory);

            Assert.Equal("served from windows ffi file server", File.ReadAllText(Path.Combine(extractedDirectory, "registered.txt")));
        }
        finally
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task CoreBridgeDownloadsFileArchiveWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(temporaryDirectory);
        var destinationPath = Path.Combine(temporaryDirectory, "received.zip");
        var payload = Encoding.UTF8.GetBytes("archive from windows ffi server");
        string? requestedTransferId = null;
        var listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        var port = ((IPEndPoint)listener.LocalEndpoint).Port;
        var serverTask = Task.Run(async () =>
        {
            using var client = await listener.AcceptTcpClientAsync();
            await using var stream = client.GetStream();
            using var reader = new StreamReader(stream, Encoding.UTF8, leaveOpen: true);
            requestedTransferId = await reader.ReadLineAsync();
            var lengthBytes = new byte[8];
            BinaryPrimitives.WriteUInt64BigEndian(lengthBytes, (ulong)payload.Length);
            await stream.WriteAsync(lengthBytes);
            await stream.WriteAsync(payload);
        });

        try
        {
            Assert.True(new ClipPlus.Windows.CoreBridge.CoreBridge().DownloadFileArchive(
                "127.0.0.1",
                port,
                "transfer-a",
                destinationPath
            ));
            await serverTask;

            Assert.Equal("transfer-a", requestedTransferId);
            Assert.Equal(payload, File.ReadAllBytes(destinationPath));
        }
        finally
        {
            listener.Stop();
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    [Fact]
    public void CoreBridgeUdpSocketSendsAndReceivesDatagramsWhenFfiLibraryIsAvailable()
    {
        var bridge = new ClipPlus.Windows.CoreBridge.CoreBridge();
        using var receiver = bridge.OpenUdpSocket(0);
        using var sender = bridge.OpenUdpSocket(0);

        Assert.NotNull(receiver);
        Assert.NotNull(sender);
        Assert.NotEqual(0, receiver.LocalPort);

        var payload = Encoding.UTF8.GetBytes("hello from windows udp ffi");
        Assert.True(sender.SendTo(payload, "127.0.0.1", receiver.LocalPort));

        var datagram = receiver.Receive();

        Assert.NotNull(datagram);
        Assert.Equal(payload, datagram.Payload);
        Assert.Equal("127.0.0.1", datagram.SourceHost);
        Assert.NotEqual(0, datagram.SourcePort);
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

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "AGENTS.md"))
                && Directory.Exists(Path.Combine(directory.FullName, "apps")))
            {
                return directory.FullName;
            }

            directory = directory.Parent;
        }

        throw new DirectoryNotFoundException("Cannot locate ClipPlus repository root.");
    }

    private static string ExpectedGroupId(string rawKey)
    {
        return rawKey switch
        {
            "clipplus-test-key" => "21YR2N3_wcdRPmEMLiuLMA",
            _ => throw new ArgumentOutOfRangeException(nameof(rawKey), rawKey, "Missing expected group id fixture.")
        };
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
