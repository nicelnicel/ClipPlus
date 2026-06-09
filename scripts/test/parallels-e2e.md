# ClipPlus Parallels Windows 端到端测试

## 测试目标

验证 macOS 宿主机和 Parallels Windows 虚拟机能运行 ClipPlus，并在关闭 Parallels 自带剪贴板共享后，通过 ClipPlus 完成共享 Key 设置、设备确认、文字同步、日志和诊断检查。

## 测试前置条件

- macOS 宿主机在 `/Users/cc/proj/ClipPlus`。
- Parallels 中已安装 Windows。
- Windows VM 使用桥接网络，或者宿主机和虚拟机处于可互相访问的网络。
- 测试时关闭 Parallels 自带剪贴板共享。
- 不修改防火墙规则，除非用户明确确认。

## 步骤

1. 在 macOS 运行 `./scripts/dev/check.sh`。
2. 在 macOS 运行 `cargo run -p clipplus-cli -- status`，确认输出包含 `core_version`。
3. 构建 mac App：`cd apps/mac && swift test`。
4. 在 Windows VM 中打开项目目录或同步后的源码目录。
5. 在 Windows VM 中运行 `dotnet test apps/windows/ClipPlus.Windows.sln`。
6. 启动 mac App，确认菜单栏出现 ClipPlus。
7. 启动 Windows App，确认托盘出现 ClipPlus。
8. 两端输入同一个共享 Key：`clipplus-test-key`。
9. 在 mac 端允许 Windows 设备加入。
10. mac 复制 `hello from mac`，Windows 粘贴应得到相同文字。
11. Windows 复制 `hello from windows`，mac 粘贴应得到相同文字。
12. 导出诊断包，确认诊断包不包含 `clipplus-test-key`。

## 失败定位

- 如果设备发现失败，检查桥接网络和 Windows 防火墙提示。
- 如果文字同步失败，检查日志中的 `discovery`、`pairing`、`sync` 模块。
- 如果诊断包包含原始 Key，立即停止测试并修复脱敏逻辑。
