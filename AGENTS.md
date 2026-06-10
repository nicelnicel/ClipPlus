# AGENTS.md instructions for /Users/cc/proj/ClipPlus

## 回复语言

- 始终使用中文回复。
- 任何 `plan`、`spec`、`des`、`tasks` 文件都需要用中文写。

## 项目结构

- 项目内的代码要分清楚层次。
- 新增功能时优先保持模块边界清晰，避免把平台逻辑、网络传输、剪贴板监听、UI 设置混在同一个文件里。

## 工具与提效

- 在项目有需要的时候，可以在自己的插件市场寻找可用的提效工具。
- 对重复性的工作，可以创建插件来固化工作流并提升效率。

## 图片资源

- 需要图片资源时，使用 Codex 的 `gpt-image2` 生成。

## 固定测试方案

- macOS 宿主机与 Parallels Windows VM 是本项目的正式桌面端测试环境。
- Windows VM 名称为 `Windows 11`，常用 IP 为 `10.211.55.3`；macOS Parallels 网卡常用 IP 为 `10.211.55.2`。
- Windows VM 已配置 OpenSSH Server，可从 macOS 使用默认 SSH key 登录：`ssh Administrator@10.211.55.3`。
- Windows VM 内 `.NET SDK 8.0.422` 安装在 `C:\dotnet`，运行 Windows 测试优先使用：

```powershell
cd C:\Mac\Home\proj\ClipPlus\apps\windows
C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo
```

- 做 ClipPlus 自身剪贴板同步端到端测试前，必须确认 Parallels 自带剪贴板共享为 `off`，避免污染测试结果：

```bash
prlctl list --all --info | rg -n "State:|IP Addresses:|Shared clipboard mode|EFI Secure boot"
```

- 常规全量检查使用：

```bash
./scripts/dev/check.sh
```

- 需要跨 macOS/Windows 做文本剪贴板同步复验时，使用同一个测试 Key，并显式指定对端 IP，避免虚拟网络广播不稳定影响结果：

```bash
CLIPPLUS_SHARED_KEY=clipplus-test-key \
CLIPPLUS_AUTO_TRUST=1 \
CLIPPLUS_PEER_HOSTS=10.211.55.3 \
/private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac
```

Windows 端使用：

```cmd
set CLIPPLUS_SHARED_KEY=clipplus-test-key
set CLIPPLUS_AUTO_TRUST=1
set CLIPPLUS_PEER_HOSTS=10.211.55.2
cd /d C:\Mac\Home\proj\ClipPlus\apps\windows\ClipPlus.Windows\bin\Debug\net8.0-windows
C:\dotnet\dotnet.exe ClipPlus.Windows.dll
```

- Windows VM 内 `.NET` 目前安装在 `C:\dotnet`，没有注册为全局 runtime；自动化/E2E 启动 App 时优先使用 `C:\dotnet\dotnet.exe ClipPlus.Windows.dll`，不要直接运行 `ClipPlus.Windows.exe`。直接运行 apphost exe 可能报 `hostfxr.dll not found`。
- 快速同步回归可以使用 `CLIPPLUS_AUTO_TRUST=1`；测试首次确认/设备信任时不要设置 `CLIPPLUS_AUTO_TRUST`。
- 无 `CLIPPLUS_AUTO_TRUST` 的手动确认验收至少验证：
  - 双方日志只出现 `peer hello` 时，Mac 写入剪贴板不会覆盖 Windows 剪贴板基线值。
  - macOS 菜单栏 ClipPlus 面板显示 `允许全部待确认设备（1）`，点击后 Windows 日志出现 `peer trust accepted`。
  - 确认后再验证 macOS -> Windows、Windows -> macOS 两个方向文本同步。
  - 复验前后保持 Parallels 自带剪贴板共享为 `off`。
- 文本同步验收至少验证两个方向：
  - macOS `pbcopy` 写入后，Windows `Get-Clipboard -Raw` 返回相同字符串。
  - Windows `Set-Clipboard` 写入后，macOS `pbpaste` 返回相同字符串。
- 日志不得包含原始共享 Key；检查 `~/Library/Logs/ClipPlus/clipplus.log` 和 Windows `%LOCALAPPDATA%\ClipPlus\logs\clipplus.log`。

## 跨设备验收矩阵

- 每次涉及网络协议、剪贴板监听、信任确认、文件传输、诊断导出、开机启动的改动，都不能只跑单平台单元测试；至少按影响面选择下面对应项复验。
- macOS 单元测试：

```bash
cd /Users/cc/proj/ClipPlus/apps/mac
swift test
```

- Windows 单元测试必须在 Parallels Windows VM 内运行：

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo"'
```

- Rust/core 侧改动必须运行仓库全量检查：

```bash
./scripts/dev/check.sh
```

- 共享 Key、组 ID、Rust FFI、Swift/C# CoreBridge 相关改动必须额外做 FFI 真实调用验证；Swift/C# 不允许静默 fallback 到旧 SHA-256 派生：
  - Rust golden vector 必须确认 `clipplus-test-key` 派生为 `21YR2N3_wcdRPmEMLiuLMA`。
  - 文本消息运行时迁入 Rust FFI 后，必须验证 `clipplus_create_text_message_json` 真实调用；macOS 测试名为 `testCoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable`，Windows 测试名为 `CoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable`。
  - macOS Swift 测试必须使用真实 `libclipplus_ffi.dylib`；常规入口是 `./scripts/dev/check.sh`。
  - macOS App 默认加载验证使用 `./scripts/dev/build-mac-app.sh`，该脚本会把 dylib 放到 SwiftPM 可执行文件旁并运行 smoke test。
  - Windows `.NET` 构建会通过 `apps/windows/Directory.Build.targets` 生成并复制 `clipplus_ffi.dll` 到 App/Test 输出目录；Windows 测试必须在不设置 `CLIPPLUS_FFI_LIBRARY_PATH` 时也能通过 bundled DLL 测试。
  - 如果 FFI 不可用，保存共享 Key 应明确失败并提示，不得生成旧 SHA-256 group id；文本消息创建也不得静默回退到 Swift/C# 本地重复实现。

macOS FFI 验证命令：

```bash
cd /Users/cc/proj/ClipPlus
./scripts/dev/build-mac-app.sh
./scripts/dev/check.sh
```

Windows FFI 验证命令：

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "Remove-Item Env:CLIPPLUS_FFI_LIBRARY_PATH -ErrorAction SilentlyContinue; Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter '\''CoreBridgeDerivesGroupIdFromBundledFfiLibrary|CoreBridgeCreatesTextMessageJsonWhenFfiLibraryIsAvailable'\''"'
```

- 在 Parallels Windows VM 内构建 Rust crate 时，必须设置 `CARGO_TARGET_DIR` 到 Windows 本机目录（例如 `$env:TEMP/ClipPlusRustTarget`），不要使用 `C:\Mac\Home\proj\ClipPlus\target`；共享目录上 Cargo/MSVC 可能出现临时目录删除失败或文件锁异常。
- Windows FFI 验证前必须确认 MSVC linker 可用；至少检查 `where.exe link` 或 Visual Studio `vswhere.exe` 能找到包含 `Microsoft.VisualStudio.Component.VC.Tools.*` 的 Build Tools 实例。

- 文件按需传输验收至少验证一个真实跨系统方向，并在计划或提交说明中写明方向：
  - 发送端复制真实文件到系统剪贴板后，接收端日志出现 `received file offer`。
  - 在接收端通过真实 UI 点击接收，不用直接调用内部函数代替用户操作。
  - 接收端 `Downloads` 下生成 `ClipPlus-Received-<transferId>.zip`。
  - 解压后文件名和内容与源文件一致。
  - 日志出现 `downloaded file archive`，且不包含源机器本地绝对路径。
- 图片同步验收至少验证一个真实跨系统方向；如果只覆盖 32 KiB 以内的小图，需要在计划里明确这是当前 MVP 限制。
- 首次确认/信任验收必须覆盖无 `CLIPPLUS_AUTO_TRUST` 的负向路径；确认前不得同步内容，确认后才允许同步。
- 开机启动相关改动必须做系统读回验证：
  - macOS 读回 Login Item 或对应系统状态，不能只检查内存开关值。
  - Windows 读回 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` 或实际启动项状态，不能只检查 UI 绑定值。
  - macOS 真实读回可用调试 smoke test，测试会注册 Login Item、读回、注销、读回，并恢复原始状态：

```bash
cd /Users/cc/proj/ClipPlus/apps/mac
swift build
cp .build/debug/ClipPlusMac /private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac
CLIPPLUS_LOGIN_ITEM_SMOKE_TEST=1 /private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac
```

期望输出包含 `enabled_after_register=true disabled_after_unregister=true restored_original=true`。

  - Windows 真实注册表测试默认不写系统；需要显式开启：

```bash
ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/clipplus_windows_known_hosts Administrator@10.211.55.3 'powershell -NoProfile -Command "$env:CLIPPLUS_ENABLE_SYSTEM_STARTUP_TEST='\''1'\''; $env:CLIPPLUS_SYSTEM_STARTUP_EXE='\''C:/Mac/Home/proj/ClipPlus/apps/windows/ClipPlus.Windows/bin/Debug/net8.0-windows/ClipPlus.Windows.exe'\''; Set-Location C:/Mac/Home/proj/ClipPlus/apps/windows; C:/dotnet/dotnet.exe test ClipPlus.Windows.sln --nologo --filter StartupManagerWritesAndDeletesRealRunEntryWhenExplicitlyEnabled"'
```

- 诊断导出验收必须打开生成的 `ClipPlus-Diagnostics-*.zip`，检查至少包含 `status.json` 和 `clipplus.log`，并确认共享 Key、设备私钥、本地绝对文件路径不会明文泄漏。
- 做 Parallels 端到端测试前后都要确认 Parallels 自带剪贴板共享仍为 `off`。
