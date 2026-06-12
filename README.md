# ClipPlus

ClipPlus 是一个面向局域网的跨设备剪贴板工具。它当前支持 macOS 和 Windows，在同一个局域网内使用同一个共享 Key 自动发现设备，并同步文本、图片和文件。

## 当前能力

- macOS 菜单栏图标和 Windows 托盘图标。
- 极简设置：输入共享 Key、开启局域网剪贴板、开机启动。
- 同 Key 设备自动加入，不需要手动允许设备。
- 文本剪贴板双向同步。
- 小图片 inline 同步。
- 文件复制后通过局域网传输归档包。
- 设备数量显示，并可查看当前同 Key 设备的机器名和 IP。
- Windows 可发布 self-contained 单文件 exe，适合双击运行。

## 安全边界

ClipPlus 目前面向可信局域网使用，不考虑公网穿透。共享 Key 用于区分同一组设备；请不要把 Key 发给不可信设备。

当前项目仍处于开发阶段，尚未做正式安全审计，不建议在不可信网络或生产环境中使用。

## 本地构建

### Rust/core 检查

```bash
./scripts/dev/check.sh
```

### macOS App

```bash
./scripts/dev/package-mac-app.sh
./scripts/dev/package-mac-dmg.sh
```

输出位置：

```text
target/macos/ClipPlus-macOS.dmg
```

本机开发安装并启动：

```bash
./scripts/dev/package-mac-app.sh --install --open
```

### Windows 单文件 exe

在 Windows 环境中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/dev/publish-windows-single-exe.ps1 -RuntimeIdentifier win-x64
```

输出位置：

```text
target/windows-single-exe/ClipPlus.Windows.exe
```

## GitHub Actions

仓库包含 CI workflow：

- Ubuntu：Rust fmt、clippy、workspace tests。
- macOS：Rust FFI、Swift tests、mac app artifact。
- Windows：.NET tests、x64 单文件 exe artifact。

## 许可证

MIT License。详见 [LICENSE](LICENSE)。
