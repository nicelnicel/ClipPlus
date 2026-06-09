# ClipPlus 跨设备剪贴板共享设计

## 背景

ClipPlus 是一个面向个人和局域网朋友共享的跨设备剪贴板工具。首版目标是在 macOS 和 Windows 之间共享剪贴板内容，包括文字、图片和文件复制事件。macOS 端以菜单栏 App 常驻，Windows 端以系统托盘 App 常驻；点击图标可以打开设置。后续预留 iPhone 和其他手机扩展能力。

项目明确不使用 HTML UI，不采用 Electron、Tauri 或 WebView 作为首版界面方案。桌面端使用原生 UI，核心协议和业务逻辑使用 Rust 实现。

## 首版范围

首版支持：

- macOS 菜单栏 App。
- Windows 原生托盘 App。
- 局域网点对点共享，不做公网、账号或云同步。
- 使用同一个共享 Key 区分共享组。
- 新设备加入时需要共享 Key 匹配，并且需要已信任设备首次确认。
- 文字自动同步。
- 图片自动同步，受大小上限控制。
- 文件复制事件同步元数据，文件内容在目标设备粘贴或接收时按需传输。
- 全局共享开关。
- 文字、图片、文件独立开关。
- 默认已信任设备全互通。
- 可对单个已信任设备暂停同步。
- 可设置开机自动启动。
- 完整日志、诊断和诊断包导出能力。
- 使用本机 Parallels Windows 虚拟机作为正式端到端测试环境。

首版不支持：

- 公网穿透。
- 账号体系。
- 云同步。
- 完整剪贴板历史管理。
- 富文本同步。
- 文件传输断点续传。
- 手机端 App。

## 总体架构

ClipPlus 使用 Rust 核心服务加平台原生外壳。

```text
ClipPlus/
  Cargo.toml

  crates/
    clipplus-core/
    clipplus-discovery/
    clipplus-transport/
    clipplus-crypto/
    clipplus-diagnostics/
    clipplus-ffi/
    clipplus-cli/

  apps/
    mac/
      ClipPlus.xcodeproj
      ClipPlus/
        App/
        MenuBar/
        Settings/
        Clipboard/
        Startup/
        CoreBridge/
        Diagnostics/

    windows/
      ClipPlus.Windows.sln
      ClipPlus.Windows/
        App/
        Tray/
        Settings/
        Clipboard/
        Startup/
        CoreBridge/
        Diagnostics/

  docs/
    superpowers/
      specs/
      plans/

  scripts/
    dev/
    build/
    package/
    test/
```

Rust core 负责：

- 设备发现。
- 握手和加密通信。
- 共享 Key 派生和设备信任状态。
- 剪贴板同步策略。
- 文件按需传输。
- 防回环。
- 配置读写。
- 日志和诊断。

平台外壳负责：

- macOS 菜单栏图标和原生设置窗口。
- Windows 托盘图标和原生设置窗口。
- 系统剪贴板读取和写入。
- 开机启动。
- 平台权限和系统错误提示。
- 调用 Rust core 接口。

## 平台应用选择

macOS 首版使用 SwiftUI、菜单栏能力和原生设置窗口。macOS 端模块包括：

```text
MenuBarController
SettingsWindow
NativeClipboard
LoginItemManager
CoreBridge
Diagnostics
```

Windows 首版优先使用 .NET WPF、NotifyIcon 托盘和 Windows Clipboard/Shell API。Windows 端模块包括：

```text
TrayController
SettingsWindow
NativeClipboard
StartupManager
CoreBridge
Diagnostics
```

选择 WPF 的原因是托盘、剪贴板桥接和 Shell 互操作更成熟。WinUI 3 后续可以考虑，但首版优先稳定性、可调试性和系统集成。

## Core 与平台壳通信

首版使用本进程 FFI，不先做独立 daemon。

```text
mac App 进程
  -> 加载 Rust static 或 dynamic library
  -> Swift CoreBridge 调用 FFI

Windows App 进程
  -> 加载 Rust DLL
  -> C# CoreBridge 调用 FFI
```

核心接口包括：

```text
core_start()
core_stop()
core_get_status()
core_set_shared_key()
core_update_settings()
core_list_devices()
core_approve_device()
core_reject_device()
core_pause_device()
core_unpause_device()
core_publish_clipboard_event()
core_export_diagnostics()
core_subscribe_events()
```

后续如果需要独立后台服务，可以把同一套 Rust core 包装成 daemon，再让 UI 通过 IPC 调用。

## 共享 Key 与设备信任

首版安全模型是局域网点对点、共享 Key 分组、首次确认入组。

启动流程：

```text
启动 ClipPlus
  -> 读取本机配置
  -> 如果没有共享 Key
       弹出设置窗口
       用户输入 Key
       用户二次确认 Key
       保存 Key 派生信息
       启动局域网发现
  -> 如果已有共享 Key
       启动 Rust core
       启动局域网发现
       连接已信任设备
```

Key 设计：

- 原始 Key 不广播。
- 原始 Key 不写日志。
- 原始 Key 不进入诊断包。
- 原始 Key 不在设置页明文展示。
- 本地保存 Key 派生信息和校验信息。
- 安全材料优先存入 macOS Keychain 或 Windows Credential Manager / DPAPI。

每台设备第一次运行时生成长期设备身份：

```text
device_id
device_name
platform
public_key
private_key
trusted_peers
```

共享 Key 决定设备是否属于同一个共享组。设备身份决定具体某台设备是否已被信任。

## 局域网发现与首次确认

设备在局域网广播或响应发现包。发现包只包含低风险信息：

```text
group_id
device_id
device_name
platform
public_key
app_version
capabilities
```

处理逻辑：

```text
收到设备发现包
  -> group_id 不匹配：忽略
  -> group_id 匹配：
       如果 device_id 已信任且未暂停：尝试建立加密连接
       如果 device_id 未信任：进入待确认设备
```

首次确认流程：

```text
新设备启动并设置同一个 Key
  -> 已有设备发现新设备属于同一 group_id
  -> 菜单栏或托盘显示提示状态
  -> 设置页显示设备名、平台和指纹
  -> 用户点击允许
  -> 双方保存对方 device_id 和 public_key
  -> 双方建立长期信任，以后自动连接
```

一个已信任设备确认即可让新设备加入。未确认设备不能同步任何剪贴板内容。

设备状态：

```text
pending      待确认
trusted      已信任
paused       已暂停
rejected     已拒绝
offline      离线
```

暂停设备会保留信任关系，但暂时不同步。删除设备会移除信任关系。

## 修改共享 Key

设置页提供“修改 Key”。

```text
点击修改共享 Key
  -> 输入新 Key
  -> 二次确认
  -> 提示修改后会断开当前共享组
  -> 用户确认
  -> 停止当前同步
  -> 清空当前发现状态
  -> 重新派生 group_id
  -> 重新发现新组设备
```

修改 Key 等同于切换共享组。默认不继承旧组信任关系。旧的信任记录可以作为历史配置保留，但不参与新组连接。

## 剪贴板事件模型

Rust core 内部统一使用 `ClipboardEvent`：

```text
ClipboardEvent
  event_id
  origin_device_id
  created_at
  content_type
  payload_ref
  metadata
```

支持内容类型：

```text
text
image
file_list
```

文字 payload：

```text
TextPayload
  text
  encoding
  byte_size
```

图片 payload：

```text
ImagePayload
  format
  byte_size
  width
  height
  content_hash
  binary_data
```

文件 payload：

```text
FileListPayload
  transfer_id
  files[]
    file_id
    name
    size
    modified_at
    content_hash
    source_relative_path
```

文件事件只同步元数据和 `transfer_id`，不直接包含文件二进制。

## 同步策略

同步开关分为两层：

```text
全局开关
  启用或暂停所有剪贴板共享

类型开关
  共享文字
  共享图片
  共享文件
```

默认行为：

- 已信任且未暂停的设备全互通。
- 文字自动同步。
- 图片自动同步，但受大小限制。
- 文件复制事件自动同步元数据，文件内容按需传输。
- 用户可以暂停单台设备。

发布流程：

```text
用户复制内容
  -> 平台 NativeClipboard 捕获变化
  -> 转成 ClipboardEvent
  -> core 检查共享开关、类型开关、防回环和去重
  -> core 广播给在线、已信任、未暂停设备
```

接收流程：

```text
core 收到远端 ClipboardEvent
  -> 检查来源设备是否已信任且未暂停
  -> 检查类型开关是否允许
  -> 检查 event_id 是否已处理
  -> 交给平台 NativeClipboard 写入系统剪贴板
  -> 标记这次写入来源为远端事件
```

## 防回环策略

防回环是首版必做能力。

策略：

- 每个事件都有全局唯一 `event_id`。
- 每台设备保存最近处理过的事件 ID LRU 缓存。
- 平台壳写入远端剪贴板前，向 core 注册 `remote_write_guard`。
- 短时间窗口内，如果监听器看到刚刚由远端写入的内容，不再重新发布。
- 使用内容 hash 做兜底去重。

核心逻辑：

```text
on_local_clipboard_changed(snapshot)
  -> 如果命中 remote_write_guard：忽略
  -> 如果内容 hash 与最近发布相同：忽略
  -> 否则生成新 event_id 并发布
```

## 图片同步

图片同步采用保守策略。

```text
复制图片
  -> 平台壳读取图片
  -> 转为统一格式，优先 PNG
  -> 检查大小
       小于或等于上限：随事件发送
       大于上限：不发送，并提示原因
```

默认图片大小上限为 20 MB。设置页允许选择 5 MB、20 MB 或 100 MB。

首版不做图片按需传输，因为图片剪贴板内容通常没有稳定源路径。

## 文件按需传输

复制文件时，源设备只发布文件元数据。

```text
用户复制文件
  -> NativeClipboard 解析文件路径
  -> core 生成 FileListPayload
  -> 保存 transfer_id 到本地文件路径映射
  -> 向其他设备发布文件元数据
```

目标设备收到远端文件事件后，目标行为是原生粘贴时按需拉取文件：

```text
用户在 Finder 或 Explorer 粘贴
  -> 平台壳触发远程文件拉取
  -> 从源设备下载文件到目标目录
  -> 校验大小和哈希
  -> 完成粘贴
```

平台实现可能存在差异：

- macOS 可研究 NSPasteboard 文件承诺、延迟写入或临时缓存文件 URL。
- Windows 可研究 IDataObject、CF_HDROP、virtual file 或临时缓存。

如果原生延迟粘贴首版风险过高，允许降级为：

```text
菜单栏或托盘显示“可接收文件”
用户点击“接收到下载目录”
```

但产品目标仍然是按需传输到粘贴目标。

文件传输特性：

- 支持多文件。
- 支持目录并保留相对路径结构。
- 大文件流式传输，不一次性读入内存。
- 默认不覆盖已有文件，冲突时自动重命名。
- 文件事件有效期默认 30 分钟。
- 首版不要求断点续传。

## 菜单栏与托盘交互

图标状态：

```text
正常：普通图标
未设置 Key：提示状态
有新设备待确认：提示状态
同步暂停：灰色状态
错误状态：警示状态
```

快速菜单：

```text
ClipPlus

状态：已连接 2 台设备
最近同步：文字，来自 Windows-PC，刚刚

[✓] 启用剪贴板共享

设备
  Windows-PC      在线
  Office-PC       已暂停
  New-PC          等待确认...

操作
  打开设置...
  打开日志...
  导出诊断包...
  退出 ClipPlus
```

点击“启用剪贴板共享”只控制全局同步，不退出应用。“退出 ClipPlus”会停止 core、断开连接并取消剪贴板监听。

## 设置窗口

mac 和 Windows 的设置内容一致，控件使用平台原生实现。

```text
ClipPlus 设置

共享
  [开关] 启用剪贴板共享
  共享 Key：已设置
  [修改 Key]

同步内容
  [x] 文字
  [x] 图片
  图片大小上限：[20 MB v]
  [x] 文件
  文件传输方式：按需传输

设备
  待确认设备
    Windows-PC    指纹 ABCD-1234    [允许] [拒绝]

  已信任设备
    MacBook Pro   本机
    Windows-PC    在线              [暂停]
    Office-PC     离线              [移除]

系统
  [x] 开机自动启动
  日志级别：[普通 v]
  [打开日志文件夹]
  [导出诊断包]

关于
  版本：0.1.0
  Core：0.1.0
  设备 ID：xxxx
```

## 开机启动

开机启动由平台壳负责。

macOS：

```text
LoginItemManager
  - 读取当前登录项状态
  - 开启登录时启动
  - 关闭登录时启动
  - 启动失败时返回明确错误
```

Windows：

```text
StartupManager
  - 当前用户级开机启动
  - 首版优先使用 HKCU Run
  - 后续可升级为任务计划程序
```

设置页的开关必须显示系统真实状态。如果用户上次关闭“启用剪贴板共享”，开机启动后仍保持共享关闭。

## 日志系统

Rust core 使用结构化日志。实现阶段优先考虑 `tracing` 体系。

模块标签：

```text
clipplus.core.config
clipplus.core.discovery
clipplus.core.transport
clipplus.core.pairing
clipplus.core.sync
clipplus.core.clipboard
clipplus.core.file_transfer
clipplus.app.mac
clipplus.app.windows
```

日志等级：

```text
普通：info / warn / error
调试：debug + 普通
详细：trace + 调试
```

日志位置：

```text
macOS:
  ~/Library/Logs/ClipPlus/clipplus.log

Windows:
  %LOCALAPPDATA%\ClipPlus\logs\clipplus.log
```

滚动策略：

```text
单文件最大：10 MB
最多保留：5 个历史文件
总量约：50 MB
```

日志隐私规则：

- 不记录剪贴板文字正文。
- 不记录图片二进制。
- 不记录文件内容。
- 不记录原始共享 Key。
- 不记录完整设备私钥或密钥材料。
- 文件日志只记录文件名、大小、传输 ID 和错误类型。
- 设备 ID 和指纹只记录短格式。

## 调试与诊断

Rust core 提供统一诊断接口：

```text
get_runtime_status()
run_network_diagnostics()
run_clipboard_diagnostics()
run_file_transfer_diagnostics()
export_diagnostics_bundle()
set_log_level(level)
subscribe_debug_events()
```

运行状态包含：

```text
RuntimeStatus
  app_version
  core_version
  platform
  device_id
  shared_key_configured
  sharing_enabled
  enabled_content_types
  discovery_status
  connected_peer_count
  pending_peer_count
  paused_peer_count
  last_clipboard_event
  last_error
  startup_enabled
  log_level
```

网络诊断包含：

```text
NetworkDiagnostics
  discovery_port_status
  transport_port_status
  local_addresses
  multicast_or_broadcast_available
  firewall_hint
  peers_seen
  peers_connected
  last_handshake_error
```

剪贴板诊断包含：

```text
ClipboardDiagnostics
  can_read_text
  can_write_text
  can_read_image
  can_write_image
  can_read_file_list
  can_write_file_list
  last_local_change_at
  last_remote_write_at
  loop_guard_active
```

文件传输诊断包含：

```text
FileTransferDiagnostics
  active_transfers
  recent_transfer_errors
  temp_cache_dir
  download_dir_access
  max_file_event_age
```

## 诊断包

设置页提供“导出诊断包”。

```text
clipplus-diagnostics-YYYYMMDD-HHMMSS.zip
  summary.json
  runtime-status.json
  network-diagnostics.json
  clipboard-diagnostics.json
  file-transfer-diagnostics.json
  logs/
    clipplus.log
    clipplus.log.1
  config-redacted.json
```

`config-redacted.json` 只包含脱敏信息：

```text
shared_key_configured: true
group_id_prefix: "ab12cd34"
device_id_prefix: "ef56gh78"
trusted_peer_count: 2
paused_peer_count: 1
content_types_enabled: ["text", "image", "file"]
startup_enabled: true
```

诊断包不能包含原始 Key、私钥、可恢复密钥材料、剪贴板正文、图片内容或文件内容。

## Parallels Windows 测试环境

本机 Parallels Windows 虚拟机作为首版正式端到端测试环境。

测试拓扑：

```text
macOS 宿主机：运行 mac 菜单栏 App
Windows 虚拟机：运行 Windows 托盘 App
网络：优先使用桥接网络
```

测试要求：

- 测试时关闭 Parallels 自带共享剪贴板，避免干扰结果。
- Windows VM 和 macOS 宿主机需要处于可互相发现的局域网环境。
- Windows 防火墙可能阻止发现或传输，诊断页需要给出提示。
- mac 日志固定在 `~/Library/Logs/ClipPlus/`。
- Windows 日志固定在 `%LOCALAPPDATA%\ClipPlus\logs\`。
- 后续可以使用 Computer Use 操作 Parallels 和 Windows UI 做真实端到端测试。
- 涉及改 Windows 系统设置、安装运行新软件、修改防火墙规则时，需要在动作前确认。

## 测试矩阵

基础测试：

```text
mac 启动后未设置 Key，弹出设置
Windows 启动后未设置 Key，弹出设置
设置相同 Key 后，设备进入待确认
允许后双方显示在线
```

同步测试：

```text
mac 复制文字 -> Windows 可粘贴
Windows 复制文字 -> mac 可粘贴
mac 复制图片 -> Windows 可粘贴
Windows 复制图片 -> mac 可粘贴
mac 复制文件 -> Windows 按需接收
Windows 复制文件 -> mac 按需接收
```

控制测试：

```text
关闭全局共享后不再同步
关闭图片同步后图片不再同步
暂停某台设备后不再互通
修改 Key 后旧设备断开，需要重新确认
```

系统测试：

```text
mac 开机启动状态可读写
Windows 开机启动状态可读写
应用退出后后台服务停止
应用重新启动后恢复配置
```

调试测试：

```text
日志文件生成并滚动
普通日志不包含剪贴板正文
调试日志包含握手、发现、同步状态
诊断包能成功导出
诊断包不包含 Key 和剪贴板内容
```

## 异常状态

错误提示需要可行动。

```text
共享 Key 未设置
  -> 打开设置并聚焦 Key 输入

发现不到设备
  -> 提示检查同一局域网、Parallels 桥接网络、防火墙

设备等待确认
  -> 展示设备名、平台、指纹、允许和拒绝

Key 不匹配
  -> 不显示对方为可加入设备，只在日志里记录 key_mismatch

文件源设备离线
  -> 粘贴或接收时提示源设备不在线

图片超过上限
  -> 菜单状态显示最近一次图片未同步原因

剪贴板权限异常
  -> 提示重启 App 或检查系统权限
```

## 手机扩展预留

后续 iPhone 和其他手机端复用以下语义：

```text
共享 Key
设备身份
首次确认
已信任设备
剪贴板事件
文件按需传输
诊断状态
```

手机端不会假设具备桌面端同等后台剪贴板监听能力。

iPhone 端后续更适合：

- 用户主动触发发送剪贴板。
- Share Sheet 发送文本、图片或文件到设备。
- 用户主动拉取最近一次共享内容。

Android 端后续根据权限能力评估是否做更自动化的同步。

核心事件模型需要同时支持：

```text
自动发布：桌面端
用户触发发布：手机端
用户触发接收：手机端
```

## 成功标准

首版完成后应满足：

- macOS 和 Windows 都能常驻运行。
- 未设置 Key 时能引导用户设置。
- 同 Key 设备能互相发现，但新设备必须确认后才能同步。
- 文字和图片能双向同步。
- 文件复制事件能双向同步，并支持按需局域网传输。
- 全局开关、类型开关和单设备暂停生效。
- 开机启动开关在 macOS 和 Windows 都可读写。
- 日志、诊断接口和诊断包可用于定位问题。
- Parallels Windows VM 能完成端到端测试。
- 日志和诊断包不泄露 Key、剪贴板正文、图片内容和文件内容。
