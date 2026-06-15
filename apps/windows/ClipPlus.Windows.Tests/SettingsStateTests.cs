using System.Buffers.Binary;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using ClipPlus.Windows.Clipboard;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Startup;
using ClipPlus.Windows.Diagnostics;
using ClipPlus.Windows.Update;
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
    public void WindowsSingleInstanceLockRejectsSecondRunningCopy()
    {
        var lockName = $"ClipPlus.Tests.{Guid.NewGuid():N}";
        using var firstLock = ClipPlus.Windows.SingleInstanceLock.Acquire(lockName);
        using var secondLock = ClipPlus.Windows.SingleInstanceLock.Acquire(lockName);

        Assert.NotNull(firstLock);
        Assert.Null(secondLock);
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
    public void FileSharedKeyVaultMigratesLegacyProcessDirectoryKeyToStableUserPath()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusTests-{Guid.NewGuid():N}");
        var stableKeyPath = Path.Combine(directory, "stable", "clipplus.shared-key");
        var legacyKeyPath = Path.Combine(directory, "legacy", "clipplus.shared-key");
        Directory.CreateDirectory(Path.GetDirectoryName(legacyKeyPath)!);
        File.WriteAllText(legacyKeyPath, "clipplus-test-key");
        try
        {
            var vault = new FileSharedKeyVault(stableKeyPath, legacyKeyPath);

            Assert.Equal("clipplus-test-key", vault.LoadSharedKey());
            Assert.Equal("clipplus-test-key", File.ReadAllText(stableKeyPath));
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
        Assert.Contains("AppVersion.SettingsWindowTitle", settingsCode);
        Assert.Contains("AppVersion.TrayText", traySource);
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
        var versionPath = Path.Combine(repositoryRoot, "VERSION");
        var bumpVersionScriptPath = Path.Combine(repositoryRoot, "scripts", "dev", "bump-version.sh");
        var checkReleaseVersionScriptPath = Path.Combine(
            repositoryRoot,
            "scripts",
            "dev",
            "check-release-version.sh"
        );
        var updateManifestScriptPath = Path.Combine(
            repositoryRoot,
            "scripts",
            "dev",
            "generate-update-manifest.sh"
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
        Assert.True(File.Exists(versionPath), $"Missing release VERSION file: {versionPath}");
        Assert.True(File.Exists(bumpVersionScriptPath), $"Missing version bump script: {bumpVersionScriptPath}");
        Assert.True(
            File.Exists(checkReleaseVersionScriptPath),
            $"Missing release version check script: {checkReleaseVersionScriptPath}"
        );
        Assert.True(
            File.Exists(updateManifestScriptPath),
            $"Missing update manifest script: {updateManifestScriptPath}"
        );
        var releaseVersion = File.ReadAllText(versionPath).Trim();
        Assert.Matches(@"^\d+\.\d+\.\d+$", releaseVersion);
        var project = File.ReadAllText(projectPath);
        Assert.Contains("<OutputType>WinExe</OutputType>", project);
        Assert.Contains("<UseWPF>true</UseWPF>", project);
        Assert.Contains("<ApplicationIcon>Resources\\ClipPlus.ico</ApplicationIcon>", project);
        Assert.Contains($"<Version>{releaseVersion}</Version>", project);
        Assert.Contains($"<AssemblyVersion>{releaseVersion}.0</AssemblyVersion>", project);
        Assert.Contains($"<FileVersion>{releaseVersion}.0</FileVersion>", project);
        Assert.Contains($"<InformationalVersion>{releaseVersion}</InformationalVersion>", project);
        Assert.Contains("ExtractAssociatedIcon", File.ReadAllText(trayControllerPath));
        var publishScript = File.ReadAllText(publishScriptPath);
        Assert.Contains("clipplus.shared-key", publishScript);
        Assert.Contains("$preservedSharedKey", publishScript);
        var bumpVersionScript = File.ReadAllText(bumpVersionScriptPath);
        Assert.Contains("VERSION", bumpVersionScript);
        Assert.Contains("Cargo.toml", bumpVersionScript);
        Assert.Contains("Cargo.lock", bumpVersionScript);
        Assert.Contains("ClipPlus.Windows.csproj", bumpVersionScript);
        Assert.Contains("CoreBridge.swift", bumpVersionScript);
        Assert.Contains("CoreBridge.cs", bumpVersionScript);
        var checkReleaseVersionScript = File.ReadAllText(checkReleaseVersionScriptPath);
        Assert.Contains("Release tag", checkReleaseVersionScript);
        Assert.Contains("VERSION", checkReleaseVersionScript);
        Assert.Contains("Cargo.lock", checkReleaseVersionScript);
        var updateManifestScript = File.ReadAllText(updateManifestScriptPath);
        Assert.Contains("clipplus-update.json", updateManifestScript);
        Assert.Contains("ClipPlus-macOS.dmg", updateManifestScript);
        Assert.Contains("ClipPlus-Windows-x64-full.exe", updateManifestScript);
        Assert.Contains("ClipPlus-Windows-x64-runtime-dependent.exe", updateManifestScript);
        Assert.Contains("browser_download_url", updateManifestScript);
        Assert.Contains("sha256:", updateManifestScript);
    }

    [Fact]
    public void WindowsUpdateVersionComparisonHandlesSemanticVersions()
    {
        Assert.True(UpdateVersion.Parse("0.1.4").CompareTo(UpdateVersion.Parse("v0.1.5")) < 0);
        Assert.True(UpdateVersion.Parse("0.1.10").CompareTo(UpdateVersion.Parse("0.1.9")) > 0);
        Assert.Equal("0.1.4", UpdateVersion.Parse("v0.1.4").ToString());
        Assert.False(UpdateVersion.TryParse("dev", out _));
    }

    [Fact]
    public void WindowsUpdateFetchesStaticReleaseManifestWithoutGitHubApiRateLimit()
    {
        Assert.Equal(
            "https://github.com/nicelnicel/ClipPlus/releases/latest/download/clipplus-update.json",
            GitHubReleaseClient.LatestReleaseUri.ToString()
        );
        Assert.DoesNotContain("api.github.com", GitHubReleaseClient.LatestReleaseUri.ToString());
    }

    [Fact]
    public void WindowsUpdateSelectsFullExeReleaseAssetAndRequiresDigest()
    {
        var releaseJson = """
            {
              "tag_name": "v0.1.5",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "ClipPlus-Windows-x64-runtime-dependent.exe",
                  "browser_download_url": "https://example.com/runtime.exe",
                  "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "size": 10
                },
                {
                  "name": "ClipPlus-Windows-x64-full.exe",
                  "browser_download_url": "https://example.com/full.exe",
                  "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "size": 20
                }
              ]
            }
            """;

        var release = GitHubReleaseClient.DecodeRelease(releaseJson);
        var asset = GitHubReleaseClient.SelectWindowsAsset(
            release,
            UpdateVersion.Parse("0.1.4"),
            WindowsUpdatePackageKind.Full
        );

        Assert.Equal("0.1.5", asset.Version.ToString());
        Assert.Equal("ClipPlus-Windows-x64-full.exe", asset.Name);
        Assert.Equal("https://example.com/full.exe", asset.DownloadUrl.ToString());
        Assert.Equal(new string('b', 64), asset.Sha256Hex);
        Assert.Equal(20, asset.Size);

        var missingDigestJson = """
            {
              "tag_name": "v0.1.5",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "ClipPlus-Windows-x64-full.exe",
                  "browser_download_url": "https://example.com/full.exe",
                  "size": 20
                }
              ]
            }
            """;
        var missingDigestRelease = GitHubReleaseClient.DecodeRelease(missingDigestJson);

        var error = Assert.Throws<UpdateException>(() => GitHubReleaseClient.SelectWindowsAsset(
            missingDigestRelease,
            UpdateVersion.Parse("0.1.4"),
            WindowsUpdatePackageKind.Full
        ));
        Assert.Equal(UpdateErrorKind.MissingDigest, error.Kind);
    }

    [Fact]
    public void WindowsUpdateSelectsRuntimeDependentExeWhenCurrentExeIsRuntimeDependent()
    {
        var releaseJson = """
            {
              "tag_name": "v0.1.5",
              "draft": false,
              "prerelease": false,
              "assets": [
                {
                  "name": "ClipPlus-Windows-x64-full.exe",
                  "browser_download_url": "https://example.com/full.exe",
                  "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                  "size": 20
                },
                {
                  "name": "ClipPlus-Windows-x64-runtime-dependent.exe",
                  "browser_download_url": "https://example.com/runtime.exe",
                  "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "size": 10
                }
              ]
            }
            """;

        var release = GitHubReleaseClient.DecodeRelease(releaseJson);
        var asset = GitHubReleaseClient.SelectWindowsAsset(
            release,
            UpdateVersion.Parse("0.1.4"),
            WindowsUpdatePackageKind.RuntimeDependent
        );

        Assert.Equal("0.1.5", asset.Version.ToString());
        Assert.Equal("ClipPlus-Windows-x64-runtime-dependent.exe", asset.Name);
        Assert.Equal("https://example.com/runtime.exe", asset.DownloadUrl.ToString());
        Assert.Equal(new string('a', 64), asset.Sha256Hex);
        Assert.Equal(10, asset.Size);
    }

    [Fact]
    public void WindowsUpdatePackageKindDetectsReleaseAssetName()
    {
        Assert.Equal(
            WindowsUpdatePackageKind.RuntimeDependent,
            WindowsUpdatePackageKindDetector.DetectFromExecutablePath(
                @"C:\Users\YJY\Downloads\ClipPlus-Windows-x64-runtime-dependent.exe"
            )
        );
        Assert.Equal(
            WindowsUpdatePackageKind.Full,
            WindowsUpdatePackageKindDetector.DetectFromExecutablePath(
                @"C:\Users\YJY\Downloads\ClipPlus-Windows-x64-full.exe"
            )
        );
        Assert.Equal(
            WindowsUpdatePackageKind.Full,
            WindowsUpdatePackageKindDetector.DetectFromExecutablePath(
                @"C:\Users\YJY\Downloads\ClipPlus.Windows.exe"
            )
        );
    }

    [Fact]
    public void WindowsUpdateDownloaderVerifiesSha256()
    {
        var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusUpdate-{Guid.NewGuid():N}");
        Directory.CreateDirectory(directory);
        var payloadPath = Path.Combine(directory, "payload.bin");
        try
        {
            File.WriteAllBytes(payloadPath, Encoding.UTF8.GetBytes("clipplus update"));

            UpdateDownloader.VerifySha256(
                payloadPath,
                "6d117130cdf62d70ef384c91de7ef1de3c637afb3aef12df44fe61ba3b789b62"
            );
            var error = Assert.Throws<UpdateException>(() => UpdateDownloader.VerifySha256(
                payloadPath,
                new string('0', 64)
            ));
            Assert.Equal(UpdateErrorKind.Sha256Mismatch, error.Kind);
        }
        finally
        {
            Directory.Delete(directory, recursive: true);
        }
    }

    [Fact]
    public void WindowsUpdateInstallerScriptBacksUpReplacesAndRelaunchesExe()
    {
        var script = WindowsUpdateInstaller.CreateUpdaterScript(
            currentExePath: @"C:\ClipPlus\ClipPlus.Windows.exe",
            newExePath: @"C:\Users\YJY\AppData\Local\ClipPlus\Updates\v0.1.5\ClipPlus-Windows-x64-full.exe",
            currentProcessId: 12345
        );

        Assert.Contains("Wait-Process -Id 12345", script);
        Assert.Contains("ClipPlus.Windows.exe.old", script);
        Assert.Contains("Move-Item -LiteralPath $currentExe -Destination $backupExe", script);
        Assert.Contains("Copy-Item -LiteralPath $newExe -Destination $currentExe", script);
        Assert.Contains("Start-Process -FilePath $currentExe", script);
    }

    [Fact]
    public void WindowsSettingsUiContainsSimpleCheckUpdateButton()
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
        var settingsCode = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "Settings",
            "SettingsWindow.xaml.cs"
        ));

        Assert.Contains("检查更新", settingsXaml);
        Assert.Contains("CheckUpdate_Click", settingsXaml);
        Assert.Contains("UpdateStatusText", settingsXaml);
        Assert.Contains("检查中...", settingsCode);
        Assert.Contains("下载中", settingsCode);
        Assert.Contains("已是最新版本", settingsCode);
        Assert.DoesNotContain("MessageBox.Show(\r\n                    this,\r\n                    \"已是最新版本\"", settingsCode);
        Assert.Contains("UpdateService", settingsCode);
        Assert.DoesNotContain("自动检查更新", settingsXaml);
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
    public void CoreBridgeExtractsEmbeddedFfiToProcessScopedTempPath()
    {
        var repositoryRoot = FindRepositoryRoot();
        var coreBridgeSource = File.ReadAllText(Path.Combine(
            repositoryRoot,
            "apps",
            "windows",
            "ClipPlus.Windows",
            "CoreBridge",
            "CoreBridge.cs"
        ));

        Assert.Contains("Environment.ProcessId", coreBridgeSource);
        Assert.Contains("FileMode.Create", coreBridgeSource);
        Assert.Contains("FileShare.Read", coreBridgeSource);
        Assert.DoesNotContain("File.Create(extractionPath)", coreBridgeSource);
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
    public void ClipPlusMessageRoundTripsDirectImageOfferPayloadWithoutInlineData()
    {
        var pngData = Enumerable.Repeat((byte)0xAB, ClipPlus.Windows.Sync.ClipPlusMessage.MaxInlineImageBytes + 16)
            .ToArray();
        var message = ClipPlus.Windows.Sync.ClipPlusMessage.CreateImageOffer(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            transferId: "image-transfer-1",
            pngData: pngData,
            archivePort: 47_632
        );

        var json = message.ToJson();
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);

        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.ImageOffer, decoded.Kind);
        Assert.Equal(1, decoded.ProtocolVersion);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("image-transfer-1", decoded.TransferId);
        Assert.Equal(ClipPlus.Windows.Sync.FileTransferFormat.DirectTree, decoded.TransferFormat);
        Assert.Equal(47_632, decoded.ArchivePort);
        Assert.Equal(pngData.Length, decoded.ImageByteSize);
        Assert.Null(decoded.ImageBase64);
        Assert.Null(decoded.DecodedImageData);
        Assert.Equal(
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d",
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
    public void CoreBridgeCreatesImageOfferMessageJsonWhenFfiLibraryIsAvailable()
    {
        var pngData = Enumerable.Repeat((byte)0xAB, ClipPlus.Windows.Sync.ClipPlusMessage.MaxInlineImageBytes + 16)
            .ToArray();
        var json = new ClipPlus.Windows.CoreBridge.CoreBridge().CreateImageOfferMessageJson(
            groupId: "group-1",
            senderDeviceId: "windows-device",
            senderDeviceName: "Windows",
            transferId: "image-transfer-1",
            pngData: pngData,
            archivePort: 47_632
        );

        Assert.NotNull(json);
        var decoded = ClipPlus.Windows.Sync.ClipPlusMessage.FromJson(json);
        Assert.Equal(ClipPlus.Windows.Sync.ClipPlusMessageKind.ImageOffer, decoded.Kind);
        Assert.Equal("group-1", decoded.GroupId);
        Assert.Equal("windows-device", decoded.SenderDeviceId);
        Assert.Equal("image-transfer-1", decoded.TransferId);
        Assert.Equal(ClipPlus.Windows.Sync.FileTransferFormat.DirectTree, decoded.TransferFormat);
        Assert.Equal(47_632, decoded.ArchivePort);
        Assert.Equal(pngData.Length, decoded.ImageByteSize);
        Assert.Null(decoded.ImageBase64);
        Assert.Equal(
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d",
            decoded.ImageContentHash
        );
    }

    [Fact]
    public void ImageContentHasherMatchesRustImageHash()
    {
        var pngData = Enumerable.Repeat((byte)0xAB, ClipPlus.Windows.Sync.ClipPlusMessage.MaxInlineImageBytes + 16)
            .ToArray();

        Assert.Equal(
            "e5a22cfa04e9800c1b7c805736d6ba84b8f76fe9c5aabc203896966aab53009d",
            ClipPlus.Windows.Sync.ImageContentHasher.Sha256Hex(pngData)
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
        Assert.Equal(ClipPlus.Windows.Sync.FileTransferFormat.DirectTree, decoded.TransferFormat);
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
        Assert.Equal(ClipPlus.Windows.Sync.FileTransferFormat.DirectTree, decoded.TransferFormat);
        Assert.Equal(47_632, decoded.ArchivePort);
        Assert.Equal(new[] { item }, decoded.Files);
        Assert.DoesNotContain(@"C:\\", json);
        Assert.DoesNotContain("/Users/", json);
    }

    [Fact]
    public void RemoteFileTransferGateRejectsInFlightAndCompletedDuplicates()
    {
        var gate = new ClipPlus.Windows.Sync.RemoteFileTransferGate();

        Assert.True(gate.CanAcceptOffer("transfer-a"));
        Assert.True(gate.Begin("transfer-a"));
        Assert.False(gate.CanAcceptOffer("transfer-a"));
        Assert.False(gate.Begin("transfer-a"));

        gate.Complete("transfer-a");

        Assert.False(gate.CanAcceptOffer("transfer-a"));
        Assert.False(gate.Begin("transfer-a"));
    }

    [Fact]
    public void RemoteFileTransferGateAllowsRetryAfterFailure()
    {
        var gate = new ClipPlus.Windows.Sync.RemoteFileTransferGate();

        Assert.True(gate.Begin("transfer-a"));
        gate.Fail("transfer-a");

        Assert.True(gate.CanAcceptOffer("transfer-a"));
        Assert.True(gate.Begin("transfer-a"));
    }

    [Fact]
    public void RemoteClipboardReceiveGuardSuppressesSingleImageFileAfterRecentImageFromSameDevice()
    {
        var guardState = new ClipPlus.Windows.Sync.RemoteClipboardReceiveGuard(TimeSpan.FromSeconds(15));
        var imageTime = DateTimeOffset.FromUnixTimeSeconds(1_000);
        var imageFile = new ClipPlus.Windows.Sync.FileTransferItem("wechat-image.png", 12_881, false);

        guardState.RecordRemoteImage("windows-device", imageTime);

        Assert.True(guardState.ShouldSuppressFileOfferAfterRecentImage(
            "windows-device",
            new[] { imageFile },
            imageTime.AddSeconds(9)
        ));
        Assert.False(guardState.ShouldSuppressFileOfferAfterRecentImage(
            "other-device",
            new[] { imageFile },
            imageTime.AddSeconds(9)
        ));
        Assert.False(guardState.ShouldSuppressFileOfferAfterRecentImage(
            "windows-device",
            new[] { new ClipPlus.Windows.Sync.FileTransferItem("note.txt", 42, false) },
            imageTime.AddSeconds(9)
        ));
        Assert.False(guardState.ShouldSuppressFileOfferAfterRecentImage(
            "windows-device",
            new[] { imageFile },
            imageTime.AddSeconds(16)
        ));
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
    public async Task CoreBridgeFileServerServesRegisteredDirectFileTreeWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(temporaryDirectory);
        var sourceDirectory = Path.Combine(temporaryDirectory, "SourceFolder");
        var nestedDirectory = Path.Combine(sourceDirectory, "Nested");
        Directory.CreateDirectory(nestedDirectory);
        File.WriteAllText(Path.Combine(sourceDirectory, "root.txt"), "root from windows ffi file tree");
        File.WriteAllText(Path.Combine(nestedDirectory, "child.txt"), "nested from windows ffi file tree");
        var destinationDirectory = Path.Combine(temporaryDirectory, "received-tree");
        using var server = new ClipPlus.Windows.CoreBridge.CoreBridge().OpenFileServer(0);
        Assert.NotNull(server);
        Assert.NotEqual(0, server.LocalPort);
        Assert.True(server.RegisterTransfer("transfer-tree-a", new[] { sourceDirectory }));
        var serverTask = Task.Run(() => server.ServeNextTree());

        try
        {
            var result = new ClipPlus.Windows.CoreBridge.CoreBridge().DownloadFileTree(
                "127.0.0.1",
                server.LocalPort,
                "transfer-tree-a",
                destinationDirectory
            );
            var servedResult = await serverTask.WaitAsync(TimeSpan.FromSeconds(6));

            Assert.NotNull(result);
            Assert.NotNull(servedResult);
            Assert.Equal(2, result.FileCount);
            Assert.Equal(result.FileCount, servedResult.FileCount);
            Assert.Equal(result.ByteCount, servedResult.ByteCount);
            Assert.Contains("SourceFolder", servedResult.TopLevelPaths);
            Assert.Contains(Path.Combine(destinationDirectory, "SourceFolder"), result.TopLevelPaths);
            Assert.Equal("root from windows ffi file tree", File.ReadAllText(Path.Combine(destinationDirectory, "SourceFolder", "root.txt")));
            Assert.Equal("nested from windows ffi file tree", File.ReadAllText(Path.Combine(destinationDirectory, "SourceFolder", "Nested", "child.txt")));
        }
        finally
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    [Fact]
    public async Task CoreBridgeDownloadsDirectFileTreeWhenFfiLibraryIsAvailable()
    {
        var temporaryDirectory = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString());
        Directory.CreateDirectory(temporaryDirectory);
        var sourceDirectory = Path.Combine(temporaryDirectory, "Published");
        var nestedDirectory = Path.Combine(sourceDirectory, "Nested");
        Directory.CreateDirectory(nestedDirectory);
        File.WriteAllText(Path.Combine(sourceDirectory, "a.txt"), "alpha direct tree");
        File.WriteAllText(Path.Combine(nestedDirectory, "b.txt"), "beta direct tree");
        var destinationDirectory = Path.Combine(temporaryDirectory, "staging");
        using var server = new ClipPlus.Windows.CoreBridge.CoreBridge().OpenFileServer(0);
        Assert.NotNull(server);
        Assert.True(server.RegisterTransfer("transfer-tree-b", new[] { sourceDirectory }));
        var serverTask = Task.Run(() => server.ServeNextTree());

        try
        {
            var result = new ClipPlus.Windows.CoreBridge.CoreBridge().DownloadFileTree(
                "127.0.0.1",
                server.LocalPort,
                "transfer-tree-b",
                destinationDirectory
            );
            await serverTask.WaitAsync(TimeSpan.FromSeconds(6));

            Assert.NotNull(result);
            Assert.Equal(2, result.FileCount);
            Assert.Equal((ulong)Encoding.UTF8.GetByteCount("alpha direct tree" + "beta direct tree"), result.ByteCount);
            Assert.Single(result.TopLevelPaths);
            Assert.Equal(Path.Combine(destinationDirectory, "Published"), result.TopLevelPaths[0]);
            Assert.Equal("alpha direct tree", File.ReadAllText(Path.Combine(destinationDirectory, "Published", "a.txt")));
            Assert.Equal("beta direct tree", File.ReadAllText(Path.Combine(destinationDirectory, "Published", "Nested", "b.txt")));
        }
        finally
        {
            Directory.Delete(temporaryDirectory, recursive: true);
        }
    }

    [Fact]
    public void UdpTextSyncServiceUsesDirectFileTreeInsteadOfDownloadsZipRuntime()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            "ClipPlus.Windows",
            "Sync",
            "UdpTextSyncService.cs"
        ));

        Assert.DoesNotContain("ClipPlus-Received-", source, StringComparison.Ordinal);
        Assert.DoesNotContain("UniqueDownloadPath", source, StringComparison.Ordinal);
        Assert.DoesNotContain("DownloadFileArchive(", source, StringComparison.Ordinal);
        Assert.DoesNotContain("string.Join(\"|\"", source, StringComparison.Ordinal);
        Assert.DoesNotContain("\"Downloads\"", source, StringComparison.Ordinal);
        Assert.Contains("DownloadFileTree(", source, StringComparison.Ordinal);
        Assert.Contains("WriteFilePaths", source, StringComparison.Ordinal);
        Assert.Contains("message.TransferFormat != ClipPlus.Windows.Sync.FileTransferFormat.DirectTree", source, StringComparison.Ordinal);
        Assert.Contains("BuildFileSignature", source, StringComparison.Ordinal);
        Assert.Contains("Staging", source, StringComparison.Ordinal);
        Assert.Contains("served file tree", source, StringComparison.Ordinal);
        Assert.DoesNotContain("file transfer download failed: {error.Message}", source, StringComparison.Ordinal);
    }

    [Fact]
    public void NativeClipboardWritesSingleImageFileAsFileDropAndImage()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                var directory = Path.Combine(Path.GetTempPath(), $"ClipPlusImageClipboard-{Guid.NewGuid():N}");
                Directory.CreateDirectory(directory);
                var imagePath = Path.Combine(directory, "copied-image.png");
                try
                {
                    WriteTestPng(imagePath);
                    var clipboard = new NativeClipboard();

                    Assert.True(clipboard.WriteFilePaths(new[] { imagePath }));
                    Assert.True(System.Windows.Clipboard.ContainsFileDropList());
                    Assert.True(System.Windows.Clipboard.ContainsImage());
                    Assert.Equal(imagePath, Assert.Single(System.Windows.Clipboard.GetFileDropList().Cast<string>()));
                    var dataObject = Assert.IsAssignableFrom<System.Windows.IDataObject>(
                        System.Windows.Clipboard.GetDataObject()
                    );
                    Assert.Contains("PNG", dataObject.GetFormats(autoConvert: false));
                    Assert.Contains("image/png", dataObject.GetFormats(autoConvert: false));
                    var sourcePngData = File.ReadAllBytes(imagePath);
                    Assert.Equal(sourcePngData, ReadPngBytes(dataObject.GetData("PNG", autoConvert: false)));
                    Assert.Equal(sourcePngData, ReadPngBytes(dataObject.GetData("image/png", autoConvert: false)));
                }
                finally
                {
                    System.Windows.Clipboard.Clear();
                    Directory.Delete(directory, recursive: true);
                }
            }
            catch (Exception error)
            {
                failure = error;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        if (failure is not null)
        {
            throw failure;
        }
    }

    [Fact]
    public void NativeClipboardReadsRegisteredPngClipboardFormat()
    {
        RunStaClipboardTest(() =>
        {
            var pngData = CreateTestPngData();
            var dataObject = new System.Windows.DataObject();
            dataObject.SetData("PNG", new MemoryStream(pngData));

            System.Windows.Clipboard.SetDataObject(dataObject, true);
            try
            {
                Assert.False(System.Windows.Clipboard.ContainsImage());
                Assert.Equal(pngData, new NativeClipboard().ReadPngImageData());
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void NativeClipboardPrefersRegisteredPngWhenClipboardAlsoContainsImage()
    {
        RunStaClipboardTest(() =>
        {
            var pngData = CreateTestPngData();
            var dataObject = new System.Windows.DataObject();
            dataObject.SetImage(CreateBitmapSourceFromPng(pngData));
            dataObject.SetData("PNG", new MemoryStream(pngData));

            System.Windows.Clipboard.SetDataObject(dataObject, true);
            try
            {
                Assert.True(System.Windows.Clipboard.ContainsImage());
                Assert.Equal(pngData, new NativeClipboard().ReadPngImageData());
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void NativeClipboardWritesPngImageAsImageAndRegisteredPngFormats()
    {
        RunStaClipboardTest(() =>
        {
            var pngData = CreateTestPngData();

            new NativeClipboard().WritePngImageData(pngData);
            try
            {
                var dataObject = Assert.IsAssignableFrom<System.Windows.IDataObject>(
                    System.Windows.Clipboard.GetDataObject()
                );

                Assert.True(System.Windows.Clipboard.ContainsImage());
                Assert.Contains("PNG", dataObject.GetFormats(autoConvert: false));
                Assert.Contains("image/png", dataObject.GetFormats(autoConvert: false));
                Assert.Equal(pngData, ReadPngBytes(dataObject.GetData("PNG", autoConvert: false)));
                Assert.Equal(pngData, ReadPngBytes(dataObject.GetData("image/png", autoConvert: false)));
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void ClipboardImageFormatsConvertsDeviceIndependentBitmapToPng()
    {
        var pngData = ClipboardImageFormats.ConvertDibToPng(CreateTestDibPayload());

        AssertPngDimensions(pngData, 24, 18);
    }

    [Fact]
    public void ClipboardImageFormatsConvertsDeviceIndependentBitmapV5ToPng()
    {
        var pngData = ClipboardImageFormats.ConvertDibToPng(CreateTestDibV5Payload());

        AssertPngDimensions(pngData, 4, 3);
    }

    [Fact]
    public void NativeClipboardReadsNativeDeviceIndependentBitmapV5ClipboardFormat()
    {
        RunStaClipboardTest(() =>
        {
            Assert.True(SetRawClipboardData(format: 17, CreateTestDibV5Payload()));
            try
            {
                AssertPngDimensions(new NativeClipboard().ReadPngImageData(), 4, 3);
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void NativeClipboardReadsNativeBitmapClipboardFormat()
    {
        RunStaClipboardTest(() =>
        {
            using var bitmap = new System.Drawing.Bitmap(
                5,
                4,
                System.Drawing.Imaging.PixelFormat.Format32bppArgb
            );
            using (var graphics = System.Drawing.Graphics.FromImage(bitmap))
            {
                graphics.Clear(System.Drawing.Color.FromArgb(255, 20, 120, 220));
            }

            var hBitmap = bitmap.GetHbitmap();
            Assert.True(SetRawClipboardHandle(format: 2, hBitmap));
            try
            {
                AssertPngDimensions(new NativeClipboard().ReadPngImageData(), 5, 4);
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void ClipboardImageFormatsReportsAvailableClipboardFormatsForDiagnostics()
    {
        RunStaClipboardTest(() =>
        {
            var pngData = CreateTestPngData();
            var dataObject = new System.Windows.DataObject();
            dataObject.SetData("WeChatPrivateFormat", "opaque");
            dataObject.SetData("PNG", new MemoryStream(pngData));

            System.Windows.Clipboard.SetDataObject(dataObject, true);
            try
            {
                var summary = ClipboardImageFormats.AvailableClipboardFormatsSummary();

                Assert.Contains("PNG", summary);
                Assert.Contains("WeChatPrivateFormat", summary);
                Assert.DoesNotContain("opaque", summary);
            }
            finally
            {
                System.Windows.Clipboard.Clear();
            }
        });
    }

    [Fact]
    public void UdpTextSyncServiceLogsClipboardFormatsWhenImageLikeClipboardCannotBeRead()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            "ClipPlus.Windows",
            "Sync",
            "UdpTextSyncService.cs"
        ));

        Assert.Contains("AvailableClipboardFormatsSummary", source, StringComparison.Ordinal);
        Assert.Contains("clipboard image read skipped formats=", source, StringComparison.Ordinal);
    }

    [Fact]
    public void UdpTextSyncServiceUsesDirectImageTransferForOversizedImages()
    {
        var source = File.ReadAllText(Path.Combine(
            AppContext.BaseDirectory,
            "..",
            "..",
            "..",
            "..",
            "ClipPlus.Windows",
            "Sync",
            "UdpTextSyncService.cs"
        ));

        Assert.Contains("PublishImageOffer", source, StringComparison.Ordinal);
        Assert.Contains("DownloadRemoteImageOfferAsync", source, StringComparison.Ordinal);
        Assert.Contains("case ClipPlusMessageKind.ImageOffer", source, StringComparison.Ordinal);
        Assert.Contains("ImageContentHasher.Sha256Hex", source, StringComparison.Ordinal);
        Assert.Contains("ReliableInlineImageBytes", source, StringComparison.Ordinal);
        Assert.Contains("pngData.Length <= ReliableInlineImageBytes", source, StringComparison.Ordinal);
        Assert.Contains("RegisterTemporaryImageTransferSource", source, StringComparison.Ordinal);
        Assert.Contains("DownloadFileTreeWithRetry", source, StringComparison.Ordinal);
        Assert.Contains("Task.Delay(TimeSpan.FromMilliseconds(250))", source, StringComparison.Ordinal);
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

    private static void WriteTestPng(string path)
    {
        File.WriteAllBytes(path, CreateTestPngData());
    }

    private static byte[] CreateTestPngData()
    {
        const int width = 24;
        const int height = 18;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var offset = (y * stride) + (x * 4);
                pixels[offset] = (byte)(30 + x);
                pixels[offset + 1] = (byte)(80 + y);
                pixels[offset + 2] = 190;
                pixels[offset + 3] = 255;
            }
        }

        var bitmap = BitmapSource.Create(
            width,
            height,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            pixels,
            stride
        );
        var encoder = new PngBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray();
    }

    private static BitmapSource CreateBitmapSourceFromPng(byte[] pngData)
    {
        using var stream = new MemoryStream(pngData);
        var bitmap = new BitmapImage();
        bitmap.BeginInit();
        bitmap.CacheOption = BitmapCacheOption.OnLoad;
        bitmap.StreamSource = stream;
        bitmap.EndInit();
        bitmap.Freeze();
        return bitmap;
    }

    private static byte[] ReadPngBytes(object? payload)
    {
        return payload switch
        {
            byte[] bytes => bytes,
            MemoryStream stream => stream.ToArray(),
            Stream stream => ReadAllBytes(stream),
            _ => throw new InvalidOperationException("PNG clipboard payload type is unsupported.")
        };
    }

    private static byte[] ReadAllBytes(Stream stream)
    {
        var originalPosition = stream.CanSeek ? stream.Position : 0;
        if (stream.CanSeek)
        {
            stream.Position = 0;
        }

        using var copy = new MemoryStream();
        stream.CopyTo(copy);
        if (stream.CanSeek)
        {
            stream.Position = originalPosition;
        }

        return copy.ToArray();
    }

    private static byte[] CreateTestDibPayload()
    {
        const int width = 24;
        const int height = 18;
        var stride = width * 4;
        var pixels = new byte[stride * height];
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var offset = (y * stride) + (x * 4);
                pixels[offset] = (byte)(30 + x);
                pixels[offset + 1] = (byte)(80 + y);
                pixels[offset + 2] = 190;
                pixels[offset + 3] = 255;
            }
        }

        var bitmap = BitmapSource.Create(
            width,
            height,
            96,
            96,
            PixelFormats.Bgra32,
            null,
            pixels,
            stride
        );
        var encoder = new BmpBitmapEncoder();
        encoder.Frames.Add(BitmapFrame.Create(bitmap));
        using var stream = new MemoryStream();
        encoder.Save(stream);
        return stream.ToArray()[14..];
    }

    private static byte[] CreateTestDibV5Payload()
    {
        const int headerSize = 124;
        const int width = 4;
        const int height = 3;
        const int stride = width * 4;
        var data = new byte[headerSize + (stride * height)];

        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(0), headerSize);
        BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(4), width);
        BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(8), -height);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(12), 1);
        BinaryPrimitives.WriteUInt16LittleEndian(data.AsSpan(14), 32);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(16), 3);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(20), (uint)(stride * height));
        BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(24), 3780);
        BinaryPrimitives.WriteInt32LittleEndian(data.AsSpan(28), 3780);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(40), 0x00FF0000);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(44), 0x0000FF00);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(48), 0x000000FF);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(52), 0xFF000000);
        BinaryPrimitives.WriteUInt32LittleEndian(data.AsSpan(56), 0x57696E20);

        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var offset = headerSize + (y * stride) + (x * 4);
                data[offset] = (byte)(10 + x);
                data[offset + 1] = (byte)(40 + y);
                data[offset + 2] = 220;
                data[offset + 3] = 255;
            }
        }

        return data;
    }

    private static void AssertPngDimensions(byte[]? pngData, int expectedWidth, int expectedHeight)
    {
        Assert.NotNull(pngData);
        Assert.True(ClipboardImageFormats.IsPng(pngData!));
        using var stream = new MemoryStream(pngData!);
        var decoder = BitmapDecoder.Create(
            stream,
            BitmapCreateOptions.PreservePixelFormat,
            BitmapCacheOption.OnLoad
        );

        Assert.Equal(expectedWidth, decoder.Frames[0].PixelWidth);
        Assert.Equal(expectedHeight, decoder.Frames[0].PixelHeight);
    }

    private static void RunStaClipboardTest(Action action)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                action();
            }
            catch (Exception error)
            {
                failure = error;
            }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();

        if (failure is not null)
        {
            throw failure;
        }
    }

    private static bool SetRawClipboardData(uint format, byte[] data)
    {
        const uint gmemMoveable = 0x0002;

        if (!OpenClipboard(IntPtr.Zero))
        {
            return false;
        }

        var handle = IntPtr.Zero;
        try
        {
            if (!EmptyClipboard())
            {
                return false;
            }

            handle = GlobalAlloc(gmemMoveable, (UIntPtr)data.Length);
            if (handle == IntPtr.Zero)
            {
                return false;
            }

            var pointer = GlobalLock(handle);
            if (pointer == IntPtr.Zero)
            {
                return false;
            }

            Marshal.Copy(data, 0, pointer, data.Length);
            _ = GlobalUnlock(handle);
            if (SetClipboardData(format, handle) == IntPtr.Zero)
            {
                return false;
            }

            handle = IntPtr.Zero;
            return true;
        }
        finally
        {
            if (handle != IntPtr.Zero)
            {
                _ = GlobalFree(handle);
            }

            _ = CloseClipboard();
        }
    }

    private static bool SetRawClipboardHandle(uint format, IntPtr handle)
    {
        if (!OpenClipboard(IntPtr.Zero))
        {
            _ = DeleteObject(handle);
            return false;
        }

        try
        {
            if (!EmptyClipboard())
            {
                _ = DeleteObject(handle);
                return false;
            }

            if (SetClipboardData(format, handle) == IntPtr.Zero)
            {
                _ = DeleteObject(handle);
                return false;
            }

            return true;
        }
        finally
        {
            _ = CloseClipboard();
        }
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool OpenClipboard(IntPtr hWndNewOwner);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool EmptyClipboard();

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool CloseClipboard();

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalAlloc(uint uFlags, UIntPtr dwBytes);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalLock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool GlobalUnlock(IntPtr hMem);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr GlobalFree(IntPtr hMem);

    [DllImport("gdi32.dll", SetLastError = true)]
    private static extern bool DeleteObject(IntPtr hObject);

    private static string FindRepositoryRoot()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            if (File.Exists(Path.Combine(directory.FullName, "Cargo.toml"))
                && Directory.Exists(Path.Combine(directory.FullName, "apps"))
                && Directory.Exists(Path.Combine(directory.FullName, "crates")))
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
