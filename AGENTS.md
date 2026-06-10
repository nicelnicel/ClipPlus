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
C:\dotnet\dotnet.exe C:\Mac\Home\proj\ClipPlus\apps\windows\ClipPlus.Windows\bin\Debug\net8.0-windows\ClipPlus.Windows.dll
```

- 文本同步验收至少验证两个方向：
  - macOS `pbcopy` 写入后，Windows `Get-Clipboard -Raw` 返回相同字符串。
  - Windows `Set-Clipboard` 写入后，macOS `pbpaste` 返回相同字符串。
- 日志不得包含原始共享 Key；检查 `~/Library/Logs/ClipPlus/clipplus.log` 和 Windows `%LOCALAPPDATA%\ClipPlus\logs\clipplus.log`。
