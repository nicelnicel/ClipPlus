# ClipPlus Parallels Windows 端到端测试

## 测试目标

验证 macOS 宿主机和 Parallels Windows 虚拟机能运行 ClipPlus，并在关闭 Parallels 自带剪贴板共享后，通过 ClipPlus 完成共享 Key 设置、设备确认、文字/图片同步、文件按需传输、日志和诊断检查。

## 测试前置条件

- macOS 宿主机在 `/Users/cc/proj/ClipPlus`。
- Parallels 中已安装 Windows，当前固定 VM 名称为 `Windows 11`。
- Windows VM 使用桥接网络，或者宿主机和虚拟机处于可互相访问的网络；当前常用 Windows IP 为 `10.211.55.3`，macOS Parallels 网卡 IP 为 `10.211.55.2`。
- Windows VM 已启用 OpenSSH Server，macOS 默认 SSH key 可登录 `ssh Administrator@10.211.55.3`。
- Windows VM 内 `.NET SDK` 安装在 `C:\dotnet`。
- 测试时关闭 Parallels 自带剪贴板共享。
- 不修改防火墙规则，除非用户明确确认。

## 步骤

1. 在 macOS 运行 `./scripts/dev/check.sh`。
2. 在 macOS 运行 `cargo run -p clipplus-cli -- status`，确认输出包含 `core_version`。
3. 构建 mac App：`cd apps/mac && swift test`。
4. 在 Windows VM 中打开项目目录或同步后的源码目录。
5. 在 Windows VM 中运行：

```powershell
cd C:\Mac\Home\proj\ClipPlus\apps\windows
C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo
```

6. 启动 mac App，确认菜单栏出现 ClipPlus。
7. 启动 Windows App，确认托盘出现 ClipPlus。当前 Windows VM 的 .NET 安装在 `C:\dotnet`，自动化测试应进入输出目录后用 `C:\dotnet\dotnet.exe ClipPlus.Windows.dll` 启动；不要直接运行 `ClipPlus.Windows.exe`，除非已确认全局 .NET runtime 注册完成。
8. 两端输入同一个共享 Key：`clipplus-test-key`。
9. 在 mac 端允许 Windows 设备加入。
10. mac 复制 `hello from mac`，Windows 粘贴应得到相同文字。
11. Windows 复制 `hello from windows`，mac 粘贴应得到相同文字。
12. 图片同步至少复验一个真实跨系统方向；若仍使用 inline UDP MVP，图片应小于 32 KiB。
13. 文件按需传输至少复验一个真实跨系统方向：
    - 发送端把真实文件复制到系统剪贴板。
    - 接收端日志出现 `received file offer`。
    - 通过真实 UI 点击接收按钮，不能直接调用内部函数代替。
    - 接收端 `Downloads` 生成 `ClipPlus-Received-<transferId>.zip`。
    - 解压 zip，确认文件名和内容与发送端源文件一致。
    - 两端日志分别出现 `served file archive` 和 `downloaded file archive`。
14. 开机启动改动要做系统读回验证；Windows 可用显式环境变量触发 HKCU Run 真实写入/读回/清理测试：

macOS 可用调试 smoke test 验证 `SMAppService.mainApp` 注册/读回/注销/读回，并恢复原始状态：

```bash
cd /Users/cc/proj/ClipPlus/apps/mac
swift build
cp .build/debug/ClipPlusMac /private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac
CLIPPLUS_LOGIN_ITEM_SMOKE_TEST=1 /private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac
```

期望输出包含 `enabled_after_register=true disabled_after_unregister=true restored_original=true`。

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "$env:CLIPPLUS_ENABLE_SYSTEM_STARTUP_TEST='\''1'\''; $env:CLIPPLUS_SYSTEM_STARTUP_EXE='\''C:/Mac/Home/proj/ClipPlus/apps/windows/ClipPlus.Windows/bin/Debug/net8.0-windows/ClipPlus.Windows.exe'\''; Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter StartupManagerWritesAndDeletesRealRunEntryWhenExplicitlyEnabled"'
```

15. 导出诊断包，确认 zip 内包含 `status.json` 和 `clipplus.log`，且不包含 `clipplus-test-key`。

## 文件传输示例命令

Windows -> macOS 方向可以用下面命令在 Windows 侧设置 FileDropList：

```bash
prlctl exec "Windows 11" --current-user powershell -NoProfile -Command "\$dir=Join-Path \$env:TEMP 'ClipPlusE2E'; New-Item -ItemType Directory -Force -Path \$dir | Out-Null; \$path=Join-Path \$dir 'windows-source.txt'; Set-Content -Path \$path -Value ([string][DateTimeOffset]::UtcNow.ToUnixTimeSeconds()); Set-Clipboard -Path \$path; Start-Sleep -Milliseconds 500; \$files=Get-Clipboard -Format FileDropList; Write-Output \$path; Write-Output ('ClipboardFiles=' + \$files.Count); foreach (\$file in \$files) { Write-Output \$file.FullName }"
```

macOS 菜单栏出现远端文件 offer 后，用 Accessibility 点击菜单栏面板里的接收按钮。完成后解压最新下载包并比对 Windows 源文件：

```bash
tmpdir=$(mktemp -d /tmp/clipplus-received.XXXXXX)
unzip -q ~/Downloads/ClipPlus-Received-<transferId>.zip -d "$tmpdir"
find "$tmpdir" -type f -maxdepth 3 -print
cat "$tmpdir/windows-source.txt"
```

## 失败定位

- 如果设备发现失败，检查桥接网络和 Windows 防火墙提示。
- 如果 `prlctl start "Windows 11"` 返回成功但 VM 很快回到 `stopped`，先检查 `/Users/cc/Library/Logs/parallels.log`。若出现 `PRL_ERR_SECURE_BOOT_VIOLATION` 或“安全启动功能防止操作系统启动”，说明 Parallels 安全启动阻止 Windows 启动；需要用户确认后再执行 `prlctl set "Windows 11" --efi-secure-boot off`。
- 如果 Parallels 配置显示 `Shared clipboard mode: on`，真实 ClipPlus 剪贴板同步验证前需要关闭 Parallels 自带共享剪贴板；这是 Parallels 设置变更，必须在动作前得到用户确认。确认后可执行 `prlctl set "Windows 11" --shared-clipboard off`。
- 如果 macOS 处于锁屏界面，菜单栏图标、设置面板和 Parallels 桌面无法做可靠视觉验证；需要先解锁宿主机再继续 Computer Use 操作。
- 如果文字同步失败，检查日志中的 `discovery`、`pairing`、`sync` 模块。
- 如果 Windows App 进程存在但 `%LOCALAPPDATA%\ClipPlus\logs\clipplus.log` 没有启动日志，先检查 Windows Application 事件日志。若出现 `You must install .NET to run this application` 或 `hostfxr.dll not found`，说明直接启动了 apphost exe；改用 `C:\dotnet\dotnet.exe ClipPlus.Windows.dll`。
- 如果文件 offer 到达但下载失败，先检查发送端 TCP `47632` 是否可从接收端访问，再检查 Windows 防火墙提示；不要在没有用户确认的情况下修改防火墙。
- 如果诊断包包含原始 Key，立即停止测试并修复脱敏逻辑。
