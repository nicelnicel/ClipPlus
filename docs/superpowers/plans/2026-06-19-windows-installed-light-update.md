# Windows 安装版轻量更新 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 Windows 安装版自动更新下载 `ClipPlus-Windows-x64-runtime-dependent.exe`，不再下载 72MB full 包。

**Architecture:** 安装器写入 `clipplus-package.json` 标记安装版。更新器优先读取该标记，安装版固定选择 runtime-dependent 资产；便携版继续按 exe 文件名判断。安装器和更新器都做 .NET 8 Desktop Runtime 检查，缺失时明确失败。

**Tech Stack:** C# / WPF / .NET 8, PowerShell 发布脚本, xUnit。

---

## 文件结构

- 修改 `apps/windows/ClipPlus.Windows/Update/UpdateModels.cs`：增加 `Installed` 包类型、安装标记路径、.NET Desktop Runtime 检测。
- 修改 `apps/windows/ClipPlus.Windows/Update/GitHubReleaseClient.cs`：`Installed` 选择 runtime-dependent 资产。
- 修改 `apps/windows/ClipPlus.Windows/Update/UpdateService.cs`：安装版更新前检查 runtime。
- 修改 `apps/windows/ClipPlus.Installer/Program.cs`：安装前检查 runtime，安装后写 `clipplus-package.json`。
- 修改 `scripts/dev/package-windows-installer.ps1`：默认嵌入 runtime-dependent 主程序包。
- 修改 `apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`：覆盖选择逻辑、安装器标记、脚本 payload、runtime guard。

### Task 1: 安装版包类型检测

**Files:**
- Modify: `apps/windows/ClipPlus.Windows/Update/UpdateModels.cs`
- Modify: `apps/windows/ClipPlus.Windows/Update/GitHubReleaseClient.cs`
- Test: `apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`

- [ ] **Step 1: 写失败测试**

在 `SettingsStateTests.cs` 增加测试：

```csharp
[Fact]
public void InstalledPackageSelectsRuntimeDependentUpdateAsset()
{
    var release = GitHubReleaseClient.DecodeRelease("""
    {
      "tag_name": "v0.1.19",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "ClipPlus-Windows-x64-full.exe",
          "browser_download_url": "https://example.com/full.exe",
          "digest": "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
          "size": 72000000
        },
        {
          "name": "ClipPlus-Windows-x64-runtime-dependent.exe",
          "browser_download_url": "https://example.com/runtime.exe",
          "digest": "sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
          "size": 2000000
        }
      ]
    }
    """);

    var asset = GitHubReleaseClient.SelectWindowsAsset(
        release,
        new UpdateVersion(0, 1, 18),
        WindowsUpdatePackageKind.Installed
    );

    Assert.Equal("ClipPlus-Windows-x64-runtime-dependent.exe", asset.Name);
    Assert.Equal("https://example.com/runtime.exe", asset.DownloadUrl.ToString());
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter InstalledPackageSelectsRuntimeDependentUpdateAsset"'
```

Expected: FAIL，`WindowsUpdatePackageKind.Installed` 不存在。

- [ ] **Step 3: 最小实现**

在 `UpdateModels.cs`：

```csharp
public enum WindowsUpdatePackageKind
{
    Full,
    RuntimeDependent,
    Installed
}
```

在 `GitHubReleaseClient.SelectWindowsAsset` 的 assetName switch：

```csharp
var assetName = packageKind switch
{
    WindowsUpdatePackageKind.RuntimeDependent => "ClipPlus-Windows-x64-runtime-dependent.exe",
    WindowsUpdatePackageKind.Installed => "ClipPlus-Windows-x64-runtime-dependent.exe",
    _ => "ClipPlus-Windows-x64-full.exe"
};
```

- [ ] **Step 4: 跑测试确认通过**

Run 同 Step 2。Expected: PASS。

### Task 2: 安装标记文件检测

**Files:**
- Modify: `apps/windows/ClipPlus.Windows/Update/UpdateModels.cs`
- Test: `apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`

- [ ] **Step 1: 写失败测试**

```csharp
[Fact]
public void InstalledPackageKindIsDetectedFromInstallDirectoryMarker()
{
    var installDirectory = Path.Combine(Path.GetTempPath(), $"ClipPlusTest-{Guid.NewGuid():N}");
    Directory.CreateDirectory(installDirectory);
    try
    {
        File.WriteAllText(
            Path.Combine(installDirectory, "clipplus-package.json"),
            """
            {"package_kind":"installed-runtime-dependent","version":"0.1.19"}
            """
        );

        Assert.Equal(
            WindowsUpdatePackageKind.Installed,
            WindowsUpdatePackageKindDetector.DetectFromExecutablePath(
                Path.Combine(installDirectory, "ClipPlus.exe")
            )
        );
    }
    finally
    {
        Directory.Delete(installDirectory, recursive: true);
    }
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter InstalledPackageKindIsDetectedFromInstallDirectoryMarker"'
```

Expected: FAIL，仍返回 `Full`。

- [ ] **Step 3: 最小实现**

在 `WindowsUpdatePackageKindDetector` 增加：

```csharp
public const string PackageMarkerFileName = "clipplus-package.json";

public static WindowsUpdatePackageKind DetectFromExecutablePath(string? executablePath)
{
    var fileName = string.IsNullOrWhiteSpace(executablePath)
        ? string.Empty
        : Path.GetFileName(executablePath);
    var directory = string.IsNullOrWhiteSpace(executablePath)
        ? string.Empty
        : Path.GetDirectoryName(executablePath);

    if (string.Equals(fileName, "ClipPlus.exe", StringComparison.OrdinalIgnoreCase)
        && !string.IsNullOrWhiteSpace(directory)
        && File.Exists(Path.Combine(directory, PackageMarkerFileName)))
    {
        return WindowsUpdatePackageKind.Installed;
    }

    return fileName.Contains("runtime-dependent", StringComparison.OrdinalIgnoreCase)
        ? WindowsUpdatePackageKind.RuntimeDependent
        : WindowsUpdatePackageKind.Full;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run 同 Step 2。Expected: PASS。

### Task 3: 安装器使用轻量 payload 并写标记

**Files:**
- Modify: `scripts/dev/package-windows-installer.ps1`
- Modify: `apps/windows/ClipPlus.Installer/Program.cs`
- Test: `apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`

- [ ] **Step 1: 写失败测试**

在现有安装器脚本测试附近新增：

```csharp
[Fact]
public void WindowsInstallerUsesRuntimeDependentPayloadAndWritesPackageMarker()
{
    var repositoryRoot = RepositoryRoot();
    var script = File.ReadAllText(Path.Combine(repositoryRoot, "scripts/dev/package-windows-installer.ps1"));
    var installerSource = File.ReadAllText(Path.Combine(repositoryRoot, "apps/windows/ClipPlus.Installer/Program.cs"));

    Assert.Contains("ClipPlus-Windows-x64-runtime-dependent.exe", script);
    Assert.DoesNotContain("defaultFullExePath", script);
    Assert.Contains("clipplus-package.json", installerSource);
    Assert.Contains("installed-runtime-dependent", installerSource);
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter WindowsInstallerUsesRuntimeDependentPayloadAndWritesPackageMarker"'
```

Expected: FAIL，脚本仍引用 full payload，安装器未写标记。

- [ ] **Step 3: 最小实现**

`package-windows-installer.ps1` 改默认 payload：

```powershell
$defaultRuntimeDependentExePath = Join-Path $repoRoot "target\windows-release\ClipPlus-Windows-x64-runtime-dependent.exe"
$fallbackRuntimeDependentExePath = Join-Path $repoRoot "target\windows-runtime-dependent\ClipPlus.Windows.exe"

if ([string]::IsNullOrWhiteSpace($FullExePath)) {
    $FullExePath = $defaultRuntimeDependentExePath
}

if (!(Test-Path $FullExePath) -and (Test-Path $fallbackRuntimeDependentExePath)) {
    $FullExePath = $fallbackRuntimeDependentExePath
}
```

`Program.cs` 安装成功写标记：

```csharp
private const string PackageMarkerFileName = "clipplus-package.json";

private static void WritePackageMarker(string installDirectory)
{
    File.WriteAllText(
        Path.Combine(installDirectory, PackageMarkerFileName),
        $$"""
        {"package_kind":"installed-runtime-dependent","version":"{{Version()}}"}
        """
    );
}
```

在 `Install()` 里 `WriteUninstallRegistry(...)` 前调用：

```csharp
WritePackageMarker(installDirectory);
```

- [ ] **Step 4: 跑测试确认通过**

Run 同 Step 2。Expected: PASS。

### Task 4: Runtime guard

**Files:**
- Modify: `apps/windows/ClipPlus.Windows/Update/UpdateModels.cs`
- Modify: `apps/windows/ClipPlus.Windows/Update/UpdateService.cs`
- Modify: `apps/windows/ClipPlus.Installer/Program.cs`
- Test: `apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`

- [ ] **Step 1: 写失败测试**

用源码级测试先锁住 guard，避免引入 registry mock：

```csharp
[Fact]
public void InstalledRuntimeDependentPathChecksDesktopRuntimeBeforeInstallOrUpdate()
{
    var repositoryRoot = RepositoryRoot();
    var updateModels = File.ReadAllText(Path.Combine(repositoryRoot, "apps/windows/ClipPlus.Windows/Update/UpdateModels.cs"));
    var updateService = File.ReadAllText(Path.Combine(repositoryRoot, "apps/windows/ClipPlus.Windows/Update/UpdateService.cs"));
    var installerSource = File.ReadAllText(Path.Combine(repositoryRoot, "apps/windows/ClipPlus.Installer/Program.cs"));

    Assert.Contains("DotNetDesktopRuntimeDetector", updateModels);
    Assert.Contains("HasDotNet8DesktopRuntime", updateModels);
    Assert.Contains("packageKind == WindowsUpdatePackageKind.Installed", updateService);
    Assert.Contains("UpdateErrorKind.UnsupportedRuntime", updateService);
    Assert.Contains("HasDotNet8DesktopRuntime", installerSource);
}
```

- [ ] **Step 2: 跑测试确认失败**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter InstalledRuntimeDependentPathChecksDesktopRuntimeBeforeInstallOrUpdate"'
```

Expected: FAIL，runtime guard 不存在。

- [ ] **Step 3: 最小实现**

在 `UpdateModels.cs` 增加：

```csharp
using Microsoft.Win32;

public static class DotNetDesktopRuntimeDetector
{
    public static bool HasDotNet8DesktopRuntime()
    {
        using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App");
        return key?.GetValueNames().Any(name => name.StartsWith("8.", StringComparison.Ordinal)) == true;
    }
}
```

在 `UpdateService.CheckAndDownloadLatestAsync` 选出 `packageKind` 后加：

```csharp
if (packageKind == WindowsUpdatePackageKind.Installed
    && !DotNetDesktopRuntimeDetector.HasDotNet8DesktopRuntime())
{
    throw new UpdateException(UpdateErrorKind.UnsupportedRuntime);
}
```

在安装器 `Program.cs` 增加同名本地检测函数；安装开始先检查，失败时抛出：

```csharp
if (!HasDotNet8DesktopRuntime())
{
    throw new InvalidOperationException("ClipPlus 安装版需要 .NET 8 Desktop Runtime。");
}
```

- [ ] **Step 4: 跑测试确认通过**

Run 同 Step 2。Expected: PASS。

### Task 5: 验证与提交

**Files:**
- All changed files above.

- [ ] **Step 1: Windows 单元测试**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo"'
```

Expected: all tests pass.

- [ ] **Step 2: 构建 Windows 三类发布资产**

Run:

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -ExecutionPolicy Bypass -Command "Set-Location C:/Mac/Home/proj/ClipPlus; ./scripts/dev/publish-windows-single-exe.ps1 -RuntimeIdentifier win-x64; ./scripts/dev/publish-windows-runtime-dependent.ps1 -RuntimeIdentifier win-x64; New-Item -ItemType Directory -Force target/windows-release | Out-Null; Copy-Item target/windows-single-exe/ClipPlus.Windows.exe target/windows-release/ClipPlus-Windows-x64-full.exe -Force; Copy-Item target/windows-runtime-dependent/ClipPlus.Windows.exe target/windows-release/ClipPlus-Windows-x64-runtime-dependent.exe -Force; ./scripts/dev/package-windows-installer.ps1 -RuntimeIdentifier win-x64"'
```

Expected:

- `target/windows-release/ClipPlus-Windows-x64-full.exe` exists.
- `target/windows-release/ClipPlus-Windows-x64-runtime-dependent.exe` exists.
- `target/windows-installer/ClipPlus-Windows-x64-Setup.exe` exists.

- [ ] **Step 3: 真实安装版 smoke**

Run installer in Windows VM user desktop, then verify:

```powershell
$installDir = Join-Path $env:LOCALAPPDATA "Programs\ClipPlus"
Test-Path (Join-Path $installDir "clipplus-package.json")
Get-Content (Join-Path $installDir "clipplus-package.json")
```

Expected: marker exists and contains `installed-runtime-dependent`.

- [ ] **Step 4: Commit**

```bash
git add apps/windows/ClipPlus.Windows/Update apps/windows/ClipPlus.Installer/Program.cs apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs scripts/dev/package-windows-installer.ps1 docs/superpowers/plans/2026-06-19-windows-installed-light-update.md
git commit -m "feat: use lightweight updates for installed Windows app"
```
