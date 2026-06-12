# ClipPlus

ClipPlus 是一个面向局域网的跨设备剪贴板工具。它支持 macOS 和 Windows，通过同一个共享 Key 在局域网内自动发现设备，并同步文字、图片和文件复制事件。

## 下载

最新版本在 [GitHub Releases](https://github.com/nicelnicel/ClipPlus/releases/latest) 下载。

- macOS：下载 `ClipPlus-macOS.dmg`，打开后运行 `ClipPlus.app`。
- Windows x64：下载 `ClipPlus-Windows-x64.exe`，双击运行。

当前 macOS 构建尚未做 Apple notarization。首次打开时如果被系统拦截，需要在系统设置里允许打开。

## 功能

- macOS 菜单栏图标和 Windows 托盘图标。
- 极简设置：共享 Key、开启局域网剪贴板、开机启动。
- 同 Key 设备自动发现并加入，不需要手动批准设备。
- 文本剪贴板双向同步。
- 小图片同步。
- 文件复制后通过局域网传输到对端下载目录。
- 显示当前同 Key 设备数量，并可查看机器名和 IP。

## 使用方式

1. 在同一个局域网内的每台电脑上启动 ClipPlus。
2. 输入同一个共享 Key。
3. 开启“局域网剪贴板”。
4. 在任意一台电脑复制文字、图片或文件，在另一台电脑粘贴或接收。

共享 Key 只用于区分同一组设备。把相同 Key 给局域网里的朋友后，对方也会加入同一组剪贴板。

## 安全边界

ClipPlus 当前只面向可信局域网使用，不做公网穿透，也不建议在不可信网络中使用。

项目仍处于早期阶段，尚未做正式安全审计。请不要把共享 Key 发给不可信设备。

## 许可证

MIT License。详见 [LICENSE](LICENSE)。
