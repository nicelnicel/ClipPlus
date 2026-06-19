# Windows 安装版轻量更新设计

## 背景

Windows 安装版现在由 `ClipPlus-Windows-x64-Setup.exe` 安装到：

```text
%LOCALAPPDATA%\Programs\ClipPlus\ClipPlus.exe
```

当前自动更新只按正在运行的 exe 文件名判断包类型。安装版文件名是 `ClipPlus.exe`，没有 `runtime-dependent` 标记，因此会被当成 full 包，每次更新下载约 72MB 的 `ClipPlus-Windows-x64-full.exe`。

目标是让安装版后续自动更新只下载 runtime-dependent 主程序包，下载体积降到约 2MB。

## 方案

采用安装版专用包类型标记，不做二进制差量补丁。

安装器写入：

```text
%LOCALAPPDATA%\Programs\ClipPlus\clipplus-package.json
```

内容：

```json
{
  "package_kind": "installed-runtime-dependent",
  "version": "0.1.19"
}
```

Windows 更新器判断顺序：

1. 当前进程路径是安装目录下的 `ClipPlus.exe`，且存在 `clipplus-package.json` 时，视为安装版。
2. 安装版固定选择 `ClipPlus-Windows-x64-runtime-dependent.exe`。
3. 便携版继续按文件名判断：
   - `ClipPlus-Windows-x64-runtime-dependent.exe` 选择 runtime-dependent。
   - `ClipPlus-Windows-x64-full.exe` 选择 full。
4. 判断失败时保守回退到 full，避免没有 .NET Runtime 的便携用户被更新到不可运行状态。

## 安装器调整

`package-windows-installer.ps1` 默认 payload 改为：

```text
target\windows-release\ClipPlus-Windows-x64-runtime-dependent.exe
```

安装后仍复制为：

```text
%LOCALAPPDATA%\Programs\ClipPlus\ClipPlus.exe
```

安装器同时写入 `clipplus-package.json`，让后续更新器知道这是安装版轻量更新通道。

## Runtime 前提

安装版轻量更新依赖 `.NET 8 Desktop Runtime`。

本阶段只做最小保护：

- 安装器安装前检查 .NET 8 Desktop Runtime。
- 安装版更新前检查 .NET 8 Desktop Runtime。
- 缺失时给出明确错误，不下载并替换 runtime-dependent 包。

不做自动下载 Microsoft Runtime。这个能力以后确实需要再加，避免把外部下载、代理、静默安装权限和校验一起塞进本次改动。

## Release 与 Manifest

`clipplus-update.json` 暂不增加字段，继续包含：

```text
ClipPlus-Windows-x64-full.exe
ClipPlus-Windows-x64-runtime-dependent.exe
```

安装包 `ClipPlus-Windows-x64-Setup.exe` 仍作为手动下载资产上传，不进入自动更新 manifest。

## 更新安装流程

继续复用现有单文件替换流程：

1. 下载 `ClipPlus-Windows-x64-runtime-dependent.exe`。
2. 校验 SHA-256。
3. 等待当前 `ClipPlus.exe` 退出。
4. 备份当前 `ClipPlus.exe`。
5. 复制下载文件覆盖为 `ClipPlus.exe`。
6. 启动 `ClipPlus.exe`。
7. 成功后删除备份，失败则回滚。

## 测试与验收

单元测试：

- 安装版路径加 `clipplus-package.json` 时选择 `ClipPlus-Windows-x64-runtime-dependent.exe`。
- 安装版不会选择 `ClipPlus-Windows-x64-full.exe`。
- full 便携版仍选择 full。
- runtime-dependent 便携版仍选择 runtime-dependent。
- 安装器脚本默认 payload 使用 runtime-dependent。
- 安装器源码写入 `clipplus-package.json`。
- Runtime 缺失时更新明确失败，不替换 exe。

Windows 真实验证：

- 安装包安装后，安装目录存在 `clipplus-package.json`。
- 检查更新日志显示 `package_kind=Installed`，下载文件名是 `ClipPlus-Windows-x64-runtime-dependent.exe`。
- 替换后的 `%LOCALAPPDATA%\Programs\ClipPlus\ClipPlus.exe` 能启动并显示新版本。
- full、runtime-dependent、setup 三类 Release 资产仍保留。

## 非目标

- 不做二进制 patch。
- 不做多版本差量矩阵。
- 不做自动下载安装 .NET Runtime。
- 不改变 macOS 更新链路。
