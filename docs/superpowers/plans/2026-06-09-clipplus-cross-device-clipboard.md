# ClipPlus 跨设备剪贴板首版 Implementation Plan（实现计划）

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建 ClipPlus 首版：macOS 菜单栏 App 与 Windows 托盘 App 通过 Rust core 在局域网内完成共享 Key 分组、首次确认、文字/图片同步、文件按需传输、日志诊断和 Parallels Windows 端到端测试。

**Architecture:** Rust workspace 承载核心模型、Key/信任、同步状态机、发现、传输、诊断和 FFI；macOS 使用 SwiftUI 菜单栏原生壳，Windows 使用 WPF 托盘原生壳。首版 core 以内嵌库方式运行在 App 进程内，CLI 仅用于开发调试和自动化验证。

**Tech Stack:** Rust 2021、Tokio、Serde、Tracing、Argon2、BLAKE3、Ed25519、X25519、SwiftUI、WPF、.NET、Parallels Windows VM。

---

## 范围拆分

设计文档覆盖多个子系统。本计划作为首版主计划，按可验证闭环拆成 12 个任务。执行时按顺序推进，每个任务都产生可测试软件和独立提交。

首版闭环顺序：

1. Rust workspace 与核心数据模型。
2. 配置、共享 Key、设备身份、信任状态。
3. 同步策略、防回环、诊断和日志。
4. 局域网发现、加密传输、文件按需传输。
5. FFI、CLI、macOS 原生壳、Windows 原生壳。
6. Parallels Windows 端到端测试。

本计划不包含公网、账号、云同步、完整剪贴板历史、手机端 App、文件断点续传。

## 文件结构职责

执行完成后仓库结构如下：

```text
/Users/cc/proj/ClipPlus/
  Cargo.toml
  rust-toolchain.toml
  .gitignore
  AGENTS.md

  crates/
    clipplus-core/
      Cargo.toml
      src/lib.rs
      src/config.rs
      src/device.rs
      src/event.rs
      src/sync.rs
      src/service.rs
      tests/sync_policy.rs

    clipplus-crypto/
      Cargo.toml
      src/lib.rs
      src/key.rs
      src/identity.rs
      tests/key_derivation.rs

    clipplus-diagnostics/
      Cargo.toml
      src/lib.rs
      src/redaction.rs
      src/status.rs
      src/export.rs
      tests/diagnostics_redaction.rs

    clipplus-discovery/
      Cargo.toml
      src/lib.rs
      src/packet.rs
      src/udp.rs
      tests/discovery_packet.rs

    clipplus-transport/
      Cargo.toml
      src/lib.rs
      src/message.rs
      src/session.rs
      src/file_transfer.rs
      tests/message_roundtrip.rs

    clipplus-ffi/
      Cargo.toml
      src/lib.rs
      src/api.rs
      src/types.rs
      tests/ffi_status.rs

    clipplus-cli/
      Cargo.toml
      src/main.rs
      tests/cli_status.rs

  apps/
    mac/
      Package.swift
      Sources/ClipPlusMac/App/ClipPlusApp.swift
      Sources/ClipPlusMac/MenuBar/MenuBarController.swift
      Sources/ClipPlusMac/Settings/SettingsView.swift
      Sources/ClipPlusMac/Clipboard/NativeClipboard.swift
      Sources/ClipPlusMac/Startup/LoginItemManager.swift
      Sources/ClipPlusMac/CoreBridge/CoreBridge.swift
      Tests/ClipPlusMacTests/SettingsStateTests.swift

    windows/
      ClipPlus.Windows.sln
      ClipPlus.Windows/ClipPlus.Windows.csproj
      ClipPlus.Windows/App.xaml
      ClipPlus.Windows/App.xaml.cs
      ClipPlus.Windows/Tray/TrayController.cs
      ClipPlus.Windows/Settings/SettingsWindow.xaml
      ClipPlus.Windows/Settings/SettingsWindow.xaml.cs
      ClipPlus.Windows/Clipboard/NativeClipboard.cs
      ClipPlus.Windows/Startup/StartupManager.cs
      ClipPlus.Windows/CoreBridge/CoreBridge.cs
      ClipPlus.Windows.Tests/ClipPlus.Windows.Tests.csproj
      ClipPlus.Windows.Tests/SettingsStateTests.cs

  scripts/
    dev/check.sh
    test/parallels-e2e.md
```

职责边界：

- `clipplus-core`：业务状态机、剪贴板事件、同步规则、设备状态、服务生命周期。
- `clipplus-crypto`：共享 Key 派生、组 ID、设备身份密钥和指纹。
- `clipplus-diagnostics`：运行状态、日志脱敏、诊断包导出。
- `clipplus-discovery`：局域网发现包和 UDP 发现。
- `clipplus-transport`：设备消息、会话握手抽象、文件流传输。
- `clipplus-ffi`：给 Swift 和 C# 调用的稳定 C ABI。
- `clipplus-cli`：开发调试入口。
- `apps/mac`：macOS 菜单栏、设置、剪贴板桥接、开机启动。
- `apps/windows`：Windows 托盘、设置、剪贴板桥接、开机启动。

---

### Task 1: 初始化 Rust workspace 与仓库基础文件

**Files:**
- Create: `/Users/cc/proj/ClipPlus/Cargo.toml`
- Create: `/Users/cc/proj/ClipPlus/rust-toolchain.toml`
- Create: `/Users/cc/proj/ClipPlus/.gitignore`
- Create: `/Users/cc/proj/ClipPlus/crates/*/Cargo.toml`
- Create: `/Users/cc/proj/ClipPlus/crates/*/src/lib.rs`
- Create: `/Users/cc/proj/ClipPlus/crates/clipplus-cli/src/main.rs`
- Create: `/Users/cc/proj/ClipPlus/scripts/dev/check.sh`

- [ ] **Step 1: 写入 workspace 清单**

Create `/Users/cc/proj/ClipPlus/Cargo.toml`:

```toml
[workspace]
members = [
  "crates/clipplus-core",
  "crates/clipplus-crypto",
  "crates/clipplus-diagnostics",
  "crates/clipplus-discovery",
  "crates/clipplus-transport",
  "crates/clipplus-ffi",
  "crates/clipplus-cli"
]
resolver = "2"

[workspace.package]
edition = "2021"
version = "0.1.0"
license = "MIT"

[workspace.dependencies]
anyhow = "1"
argon2 = "0.5"
base64 = "0.22"
blake3 = "1"
chrono = { version = "0.4", features = ["serde"] }
ed25519-dalek = { version = "2", features = ["rand_core"] }
rand_core = { version = "0.6", features = ["getrandom"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
thiserror = "1"
tokio = { version = "1", features = ["macros", "net", "rt-multi-thread", "time", "sync", "fs", "io-util"] }
tracing = "0.1"
uuid = { version = "1", features = ["v4", "serde"] }
x25519-dalek = "2"
zip = "2"
```

- [ ] **Step 2: 固定 Rust toolchain**

Create `/Users/cc/proj/ClipPlus/rust-toolchain.toml`:

```toml
[toolchain]
channel = "stable"
components = ["rustfmt", "clippy"]
```

- [ ] **Step 3: 写入忽略规则**

Create `/Users/cc/proj/ClipPlus/.gitignore`:

```gitignore
/target/
/.idea/
/.vscode/
.DS_Store
*.log
*.tmp
*.zip
apps/windows/**/bin/
apps/windows/**/obj/
apps/mac/.build/
apps/mac/DerivedData/
```

- [ ] **Step 4: 创建每个 crate 的最小清单和 lib**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-core/Cargo.toml`:

```toml
[package]
name = "clipplus-core"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
chrono.workspace = true
serde.workspace = true
thiserror.workspace = true
uuid.workspace = true

[dev-dependencies]
serde_json.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/lib.rs`:

```rust
pub mod config;
pub mod device;
pub mod event;
pub mod service;
pub mod sync;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/Cargo.toml`:

```toml
[package]
name = "clipplus-crypto"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
argon2.workspace = true
base64.workspace = true
blake3.workspace = true
ed25519-dalek.workspace = true
rand_core.workspace = true
serde.workspace = true
thiserror.workspace = true
uuid.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/src/lib.rs`:

```rust
pub mod identity;
pub mod key;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/Cargo.toml`:

```toml
[package]
name = "clipplus-diagnostics"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
chrono.workspace = true
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
zip.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/lib.rs`:

```rust
pub mod export;
pub mod redaction;
pub mod status;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/Cargo.toml`:

```toml
[package]
name = "clipplus-discovery"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
tokio.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/lib.rs`:

```rust
pub mod packet;
pub mod udp;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-transport/Cargo.toml`:

```toml
[package]
name = "clipplus-transport"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
tokio.workspace = true
uuid.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/lib.rs`:

```rust
pub mod file_transfer;
pub mod message;
pub mod session;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/Cargo.toml`:

```toml
[package]
name = "clipplus-ffi"
version.workspace = true
edition.workspace = true
license.workspace = true

[lib]
crate-type = ["staticlib", "cdylib", "rlib"]

[dependencies]
clipplus-core = { path = "../clipplus-core" }
clipplus-diagnostics = { path = "../clipplus-diagnostics" }
serde.workspace = true
serde_json.workspace = true
thiserror.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/lib.rs`:

```rust
pub mod api;
pub mod types;
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-cli/Cargo.toml`:

```toml
[package]
name = "clipplus-cli"
version.workspace = true
edition.workspace = true
license.workspace = true

[dependencies]
anyhow.workspace = true
clipplus-core = { path = "../clipplus-core" }
clipplus-diagnostics = { path = "../clipplus-diagnostics" }
serde_json.workspace = true
```

Create `/Users/cc/proj/ClipPlus/crates/clipplus-cli/src/main.rs`:

```rust
fn main() {
    println!("clipplus-cli 0.1.0");
}
```

- [ ] **Step 5: 写入统一检查脚本**

Create `/Users/cc/proj/ClipPlus/scripts/dev/check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
```

Run:

```bash
chmod +x scripts/dev/check.sh
```

- [ ] **Step 6: 运行首次检查，确认缺失模块失败**

Run:

```bash
cargo test --workspace
```

Expected: FAIL，错误包含 `file not found for module`，因为 `config.rs`、`device.rs` 等模块尚未创建。

- [ ] **Step 7: 创建空模块让 workspace 编译通过**

Create these empty files:

```text
crates/clipplus-core/src/config.rs
crates/clipplus-core/src/device.rs
crates/clipplus-core/src/event.rs
crates/clipplus-core/src/service.rs
crates/clipplus-core/src/sync.rs
crates/clipplus-crypto/src/key.rs
crates/clipplus-crypto/src/identity.rs
crates/clipplus-diagnostics/src/redaction.rs
crates/clipplus-diagnostics/src/status.rs
crates/clipplus-diagnostics/src/export.rs
crates/clipplus-discovery/src/packet.rs
crates/clipplus-discovery/src/udp.rs
crates/clipplus-transport/src/message.rs
crates/clipplus-transport/src/session.rs
crates/clipplus-transport/src/file_transfer.rs
crates/clipplus-ffi/src/api.rs
crates/clipplus-ffi/src/types.rs
```

Each empty file content:

```rust
```

- [ ] **Step 8: 运行检查通过**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS，`cargo test --workspace` 输出所有 crate 编译通过。

- [ ] **Step 9: 提交**

```bash
git add Cargo.toml rust-toolchain.toml .gitignore crates scripts/dev/check.sh
git commit -m "chore: initialize Rust workspace"
```

---

### Task 2: 核心领域模型与同步设置

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/config.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/device.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/event.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`:

```rust
use chrono::Utc;
use clipplus_core::config::{ContentTypeSettings, ImageLimit, SyncSettings};
use clipplus_core::device::{DeviceId, DeviceState, PeerDevice, Platform};
use clipplus_core::event::{ClipboardEvent, ClipboardPayload, FileItem, ImageFormat};
use uuid::Uuid;

fn test_device_id() -> DeviceId {
    DeviceId::new("test-device").unwrap()
}

fn text_event(text: &str) -> ClipboardEvent {
    ClipboardEvent::new_text(test_device_id(), text)
}

fn image_event(byte_size: usize) -> ClipboardEvent {
    ClipboardEvent::new_image_metadata(
        test_device_id(),
        ImageFormat::Png,
        byte_size,
        100,
        100,
        format!("test-image-{byte_size}"),
    )
}

fn file_list_event() -> ClipboardEvent {
    ClipboardEvent {
        event_id: Uuid::new_v4(),
        origin_device_id: test_device_id(),
        created_at: Utc::now(),
        payload: ClipboardPayload::FileList {
            transfer_id: Uuid::new_v4(),
            files: vec![FileItem {
                file_id: Uuid::new_v4(),
                name: "document.txt".to_string(),
                size: 12,
                modified_at: Utc::now(),
                content_hash: "test-file".to_string(),
                source_relative_path: "document.txt".to_string(),
            }],
        },
    }
}

#[test]
fn default_settings_enable_text_image_and_file() {
    let settings = SyncSettings::default();

    assert!(settings.sharing_enabled);
    assert!(settings.content.text);
    assert!(settings.content.image);
    assert!(settings.content.file);
    assert_eq!(settings.content.image_limit, ImageLimit::Mb20);
}

#[test]
fn paused_device_is_not_eligible_for_sync() {
    let peer = PeerDevice::new(
        DeviceId::new("peer-a").unwrap(),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Paused,
    );

    assert!(!peer.can_sync());
}

#[test]
fn device_id_trims_runtime_values() {
    let id = DeviceId::new(" peer-a ").unwrap();

    assert_eq!(id.as_str(), "peer-a");
}

#[test]
fn device_id_rejects_blank_values() {
    assert!(DeviceId::new("   ").is_err());
}

#[test]
fn device_id_from_str_uses_same_validation() {
    let id = " peer-a ".parse::<DeviceId>().unwrap();

    assert_eq!(id.as_str(), "peer-a");
    assert!("   ".parse::<DeviceId>().is_err());
}

#[test]
fn device_id_deserialization_uses_same_validation() {
    let id = serde_json::from_str::<DeviceId>("\" peer-a \"").unwrap();

    assert_eq!(id.as_str(), "peer-a");
    assert!(serde_json::from_str::<DeviceId>("\"   \"").is_err());
}

#[test]
fn image_payload_respects_configured_limit() {
    let content = ContentTypeSettings {
        text: true,
        image: true,
        file: true,
        image_limit: ImageLimit::Mb5,
    };
    let event = image_event(6 * 1024 * 1024);

    assert!(!content.allows(&event));
}

#[test]
fn text_event_is_allowed_when_text_sync_is_enabled() {
    let content = ContentTypeSettings {
        text: true,
        image: false,
        file: false,
        image_limit: ImageLimit::Mb20,
    };
    let event = text_event("hello");

    assert!(matches!(&event.payload, ClipboardPayload::Text { .. }));
    assert!(content.allows(&event));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

Expected: FAIL，错误包含 `unresolved import clipplus_core::config::SyncSettings`。

- [ ] **Step 3: 实现 config 模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/config.rs`:

```rust
use crate::event::{ClipboardEvent, ClipboardPayload};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImageLimit {
    Mb5,
    Mb20,
    Mb100,
}

impl ImageLimit {
    pub fn bytes(self) -> usize {
        match self {
            Self::Mb5 => 5 * 1024 * 1024,
            Self::Mb20 => 20 * 1024 * 1024,
            Self::Mb100 => 100 * 1024 * 1024,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentTypeSettings {
    pub text: bool,
    pub image: bool,
    pub file: bool,
    pub image_limit: ImageLimit,
}

impl Default for ContentTypeSettings {
    fn default() -> Self {
        Self {
            text: true,
            image: true,
            file: true,
            image_limit: ImageLimit::Mb20,
        }
    }
}

impl ContentTypeSettings {
    pub fn allows(&self, event: &ClipboardEvent) -> bool {
        match &event.payload {
            ClipboardPayload::Text { .. } => self.text,
            ClipboardPayload::Image { byte_size, .. } => self.image && *byte_size <= self.image_limit.bytes(),
            ClipboardPayload::FileList { .. } => self.file,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum LogLevel {
    Normal,
    Debug,
    Verbose,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SyncSettings {
    pub sharing_enabled: bool,
    pub content: ContentTypeSettings,
    pub startup_enabled_intent: bool,
    pub log_level: LogLevel,
}

impl Default for SyncSettings {
    fn default() -> Self {
        Self {
            sharing_enabled: true,
            content: ContentTypeSettings::default(),
            startup_enabled_intent: false,
            log_level: LogLevel::Normal,
        }
    }
}
```

- [ ] **Step 4: 实现 device 模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/device.rs`:

```rust
use std::str::FromStr;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DeviceIdError {
    #[error("device id cannot be empty")]
    Empty,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct DeviceId(String);

impl DeviceId {
    pub fn new(value: impl Into<String>) -> Result<Self, DeviceIdError> {
        let value = value.into();
        let trimmed = value.trim();

        if trimmed.is_empty() {
            return Err(DeviceIdError::Empty);
        }

        Ok(Self(trimmed.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for DeviceId {
    type Err = DeviceIdError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::new(value)
    }
}

impl TryFrom<String> for DeviceId {
    type Error = DeviceIdError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::new(value)
    }
}

impl From<DeviceId> for String {
    fn from(value: DeviceId) -> Self {
        value.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Platform {
    MacOS,
    Windows,
    Ios,
    Android,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceState {
    Pending,
    Trusted,
    Paused,
    Rejected,
    Offline,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PeerDevice {
    pub id: DeviceId,
    pub name: String,
    pub platform: Platform,
    pub state: DeviceState,
}

impl PeerDevice {
    pub fn new(id: DeviceId, name: impl Into<String>, platform: Platform, state: DeviceState) -> Self {
        Self {
            id,
            name: name.into(),
            platform,
            state,
        }
    }

    pub fn can_sync(&self) -> bool {
        matches!(self.state, DeviceState::Trusted)
    }
}
```

- [ ] **Step 5: 实现 event 模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/event.rs`:

```rust
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::device::DeviceId;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardEvent {
    pub event_id: Uuid,
    pub origin_device_id: DeviceId,
    pub created_at: DateTime<Utc>,
    pub payload: ClipboardPayload,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub enum ClipboardPayload {
    Text {
        text: String,
        byte_size: usize,
    },
    Image {
        format: ImageFormat,
        byte_size: usize,
        width: u32,
        height: u32,
        content_hash: String,
    },
    FileList {
        transfer_id: Uuid,
        files: Vec<FileItem>,
    },
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum ImageFormat {
    Png,
    Jpeg,
    Tiff,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct FileItem {
    pub file_id: Uuid,
    pub name: String,
    pub size: u64,
    pub modified_at: DateTime<Utc>,
    pub content_hash: String,
    pub source_relative_path: String,
}

impl ClipboardEvent {
    pub fn new_text(origin_device_id: DeviceId, text: impl Into<String>) -> Self {
        let text = text.into();
        let byte_size = text.len();

        Self {
            event_id: Uuid::new_v4(),
            origin_device_id,
            created_at: Utc::now(),
            payload: ClipboardPayload::Text { text, byte_size },
        }
    }

    pub fn new_image_metadata(
        origin_device_id: DeviceId,
        format: ImageFormat,
        byte_size: usize,
        width: u32,
        height: u32,
        content_hash: impl Into<String>,
    ) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            origin_device_id,
            created_at: Utc::now(),
            payload: ClipboardPayload::Image {
                format,
                byte_size,
                width,
                height,
                content_hash: content_hash.into(),
            },
        }
    }
}
```

- [ ] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

Expected: PASS，4 个测试通过。

- [ ] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add crates/clipplus-core
git commit -m "feat: add core clipboard models"
```

---

### Task 3: 共享 Key、设备身份与信任状态

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/src/key.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/src/identity.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/device.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/tests/key_derivation.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`

- [ ] **Step 1: 写 Key 派生失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/tests/key_derivation.rs`:

```rust
use clipplus_crypto::identity::DeviceIdentity;
use clipplus_crypto::key::SharedKeyMaterial;

#[test]
fn same_key_derives_same_group_id() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let right = SharedKeyMaterial::derive("friend-lan-key").unwrap();

    assert_eq!(left.group_id, right.group_id);
    assert_ne!(left.group_id, "friend-lan-key");
}

#[test]
fn same_key_with_whitespace_derives_same_group_id() {
    let left = SharedKeyMaterial::derive(" friend-lan-key ").unwrap();
    let right = SharedKeyMaterial::derive("friend-lan-key").unwrap();

    assert_eq!(left.group_id, right.group_id);
}

#[test]
fn different_keys_derive_different_group_ids() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let right = SharedKeyMaterial::derive("other-lan-key").unwrap();

    assert_ne!(left.group_id, right.group_id);
}

#[test]
fn verifier_is_stable_distinct_and_key_specific() {
    let left = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let same = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let other = SharedKeyMaterial::derive("other-lan-key").unwrap();

    assert_eq!(left.verifier, same.verifier);
    assert_ne!(left.verifier, other.verifier);
    assert_ne!(left.group_id, left.verifier);
}

#[test]
fn shared_key_debug_redacts_verifier() {
    let material = SharedKeyMaterial::derive("friend-lan-key").unwrap();
    let debug = format!("{:?}", material);

    assert!(debug.contains(&material.group_id));
    assert!(!debug.contains(&material.verifier));
    assert!(debug.contains("<redacted>"));
}

#[test]
fn empty_key_is_rejected() {
    let result = SharedKeyMaterial::derive("   ");

    assert!(result.is_err());
}

#[test]
fn device_identity_has_stable_fingerprint_prefix() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert_eq!(identity.fingerprint_short().len(), 9);
    assert!(identity.fingerprint_short().contains('-'));
}

#[test]
fn device_identity_exposes_non_empty_key_material() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert!(!identity.public_key.is_empty());
    assert!(!identity.private_key_material_for_local_storage().is_empty());
}

#[test]
fn device_identity_debug_redacts_private_key() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");
    let private_key = identity.private_key_material_for_local_storage();
    let debug = format!("{:?}", identity);

    assert!(debug.contains(&identity.public_key));
    assert!(!debug.contains(private_key));
    assert!(debug.contains("<redacted>"));
}

#[test]
fn device_identity_fingerprint_is_stable() {
    let identity = DeviceIdentity::generate("MacBook Pro", "macos");

    assert_eq!(identity.fingerprint_short(), identity.fingerprint_short());
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-crypto --test key_derivation
```

Expected: FAIL，错误包含 `unresolved import clipplus_crypto::key::SharedKeyMaterial`。

- [ ] **Step 3: 实现共享 Key 派生**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/src/key.rs`:

```rust
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use std::fmt;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum KeyError {
    #[error("共享 Key 不能为空")]
    Empty,
    #[error("共享 Key 派生失败: {0}")]
    Kdf(String),
}

#[derive(Clone, PartialEq, Eq)]
pub struct SharedKeyMaterial {
    pub group_id: String,
    pub verifier: String,
}

impl fmt::Debug for SharedKeyMaterial {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SharedKeyMaterial")
            .field("group_id", &self.group_id)
            .field("verifier", &"<redacted>")
            .finish()
    }
}

impl SharedKeyMaterial {
    pub fn derive(raw_key: &str) -> Result<Self, KeyError> {
        let normalized = raw_key.trim();
        if normalized.is_empty() {
            return Err(KeyError::Empty);
        }

        let argon2 = argon2::Argon2::default();
        let mut stretched = [0u8; 32];
        argon2
            .hash_password_into(
                normalized.as_bytes(),
                b"clipplus.shared-key.v1",
                &mut stretched,
            )
            .map_err(|error| KeyError::Kdf(error.to_string()))?;

        let group_hash = blake3::derive_key("clipplus.group.v1", &stretched);
        let verifier_hash = blake3::derive_key("clipplus.verifier.v1", &stretched);

        Ok(Self {
            group_id: URL_SAFE_NO_PAD.encode(&group_hash[..16]),
            verifier: URL_SAFE_NO_PAD.encode(&verifier_hash[..16]),
        })
    }
}
```

- [ ] **Step 4: 实现设备身份**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-crypto/src/identity.rs`:

```rust
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{SigningKey, VerifyingKey};
use rand_core::OsRng;
use std::fmt;
use uuid::Uuid;

#[derive(Clone, PartialEq, Eq)]
pub struct DeviceIdentity {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub public_key: String,
    private_key: String,
}

impl fmt::Debug for DeviceIdentity {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("DeviceIdentity")
            .field("device_id", &self.device_id)
            .field("device_name", &self.device_name)
            .field("platform", &self.platform)
            .field("public_key", &self.public_key)
            .field("private_key", &"<redacted>")
            .finish()
    }
}

impl DeviceIdentity {
    pub fn generate(device_name: impl Into<String>, platform: impl Into<String>) -> Self {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key: VerifyingKey = signing_key.verifying_key();

        Self {
            device_id: Uuid::new_v4().to_string(),
            device_name: device_name.into(),
            platform: platform.into(),
            public_key: URL_SAFE_NO_PAD.encode(verifying_key.to_bytes()),
            private_key: URL_SAFE_NO_PAD.encode(signing_key.to_bytes()),
        }
    }

    pub fn private_key_material_for_local_storage(&self) -> &str {
        &self.private_key
    }

    pub fn fingerprint_short(&self) -> String {
        let hash = blake3::hash(self.public_key.as_bytes()).to_hex().to_string();
        format!("{}-{}", &hash[0..4].to_uppercase(), &hash[4..8].to_uppercase())
    }
}
```

- [ ] **Step 5: 给 core 设备模型增加信任操作**

Append to `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/device.rs`:

```rust

impl PeerDevice {
    pub fn approve(&mut self) {
        self.state = DeviceState::Trusted;
    }

    pub fn pause(&mut self) {
        self.state = DeviceState::Paused;
    }

    pub fn reject(&mut self) {
        self.state = DeviceState::Rejected;
    }
}
```

Append to `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`:

```rust
#[test]
fn peer_device_trust_actions_update_sync_eligibility() {
    let mut peer = PeerDevice::new(
        DeviceId::new("peer-a").unwrap(),
        "Windows-PC",
        Platform::Windows,
        DeviceState::Pending,
    );

    peer.approve();
    assert!(peer.can_sync());

    peer.pause();
    assert!(!peer.can_sync());

    peer.approve();
    assert!(peer.can_sync());

    peer.reject();
    assert!(!peer.can_sync());
}
```

- [ ] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-crypto --test key_derivation
cargo test -p clipplus-core --test sync_policy
```

Expected: PASS，`key_derivation` 和 `sync_policy` 都通过。

- [ ] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add crates/clipplus-crypto crates/clipplus-core/src/device.rs
git commit -m "feat: add shared key and device identity"
```

---

### Task 4: 同步策略和防回环状态机

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/sync.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/service.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`

- [ ] **Step 1: 扩展失败测试**

Append to `/Users/cc/proj/ClipPlus/crates/clipplus-core/tests/sync_policy.rs`:

```rust
use clipplus_core::sync::{LoopGuard, SyncDecision, SyncPolicy};

#[test]
fn disabled_global_sharing_blocks_publish() {
    let mut settings = SyncSettings::default();
    settings.sharing_enabled = false;
    let policy = SyncPolicy::new(settings);
    let event = text_event("hello");

    assert_eq!(policy.can_publish(&event), SyncDecision::Blocked("sharing_disabled"));
}

#[test]
fn remote_write_guard_blocks_loopback() {
    let event = text_event("hello");
    let mut guard = LoopGuard::default();

    guard.mark_remote_write(event.event_id);

    assert!(guard.should_ignore_local_change(event.event_id));
}

#[test]
fn processed_event_is_not_processed_twice() {
    let event = text_event("hello");
    let mut guard = LoopGuard::default();

    assert!(!guard.has_processed(event.event_id));
    guard.mark_processed(event.event_id);
    assert!(guard.has_processed(event.event_id));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

Expected: FAIL，错误包含 `unresolved import clipplus_core::sync::LoopGuard`。

- [ ] **Step 3: 实现同步策略**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/sync.rs`:

```rust
use std::collections::VecDeque;

use uuid::Uuid;

use crate::config::SyncSettings;
use crate::event::ClipboardEvent;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SyncDecision {
    Allowed,
    Blocked(&'static str),
}

#[derive(Debug, Clone)]
pub struct SyncPolicy {
    settings: SyncSettings,
}

impl SyncPolicy {
    pub fn new(settings: SyncSettings) -> Self {
        Self { settings }
    }

    pub fn can_publish(&self, event: &ClipboardEvent) -> SyncDecision {
        if !self.settings.sharing_enabled {
            return SyncDecision::Blocked("sharing_disabled");
        }

        if !self.settings.content.allows(event) {
            return SyncDecision::Blocked("content_type_disabled_or_too_large");
        }

        SyncDecision::Allowed
    }
}

#[derive(Debug, Clone)]
pub struct LoopGuard {
    recent_remote_writes: VecDeque<Uuid>,
    recent_processed: VecDeque<Uuid>,
    capacity: usize,
}

impl Default for LoopGuard {
    fn default() -> Self {
        Self {
            recent_remote_writes: VecDeque::new(),
            recent_processed: VecDeque::new(),
            capacity: 128,
        }
    }
}

impl LoopGuard {
    pub fn mark_remote_write(&mut self, event_id: Uuid) {
        Self::push_lru(&mut self.recent_remote_writes, self.capacity, event_id);
    }

    pub fn should_ignore_local_change(&self, event_id: Uuid) -> bool {
        self.recent_remote_writes.contains(&event_id)
    }

    pub fn mark_processed(&mut self, event_id: Uuid) {
        Self::push_lru(&mut self.recent_processed, self.capacity, event_id);
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.recent_processed.contains(&event_id)
    }

    fn push_lru(queue: &mut VecDeque<Uuid>, capacity: usize, event_id: Uuid) {
        if queue.contains(&event_id) {
            return;
        }

        queue.push_back(event_id);
        while queue.len() > capacity {
            queue.pop_front();
        }
    }
}
```

- [ ] **Step 4: 实现 core 服务壳状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/service.rs`:

```rust
use crate::config::SyncSettings;
use crate::sync::{LoopGuard, SyncPolicy};

#[derive(Debug, Clone)]
pub struct CoreService {
    settings: SyncSettings,
    loop_guard: LoopGuard,
}

impl CoreService {
    pub fn new(settings: SyncSettings) -> Self {
        Self {
            settings,
            loop_guard: LoopGuard::default(),
        }
    }

    pub fn policy(&self) -> SyncPolicy {
        SyncPolicy::new(self.settings.clone())
    }

    pub fn loop_guard(&self) -> &LoopGuard {
        &self.loop_guard
    }
}
```

- [ ] **Step 5: 运行测试通过**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

Expected: PASS，新增 3 个测试通过，文件内全部测试通过。

- [ ] **Step 6: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add crates/clipplus-core
git commit -m "feat: add sync policy and loop guard"
```

---

### Task 5: 诊断状态、日志脱敏和诊断包导出

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/status.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/redaction.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/export.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/tests/diagnostics_redaction.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/tests/diagnostics_redaction.rs`:

```rust
use clipplus_diagnostics::redaction::{redact_config, RedactedConfig};
use clipplus_diagnostics::status::{ContentTypeStatus, RuntimeStatus};

#[test]
fn redacted_config_does_not_include_raw_key() {
    let redacted = redact_config(
        true,
        "raw-secret-key",
        "ab12cd34ef56",
        "device-secret-id",
        2,
        1,
    );

    assert_eq!(redacted.shared_key_configured, true);
    assert_eq!(redacted.group_id_prefix, "ab12cd34");
    assert_eq!(redacted.device_id_prefix, "device-s");
    assert!(!serde_json::to_string(&redacted).unwrap().contains("raw-secret-key"));
}

#[test]
fn runtime_status_serializes_without_clipboard_content() {
    let status = RuntimeStatus::new_for_test();
    let json = serde_json::to_string(&status).unwrap();

    assert!(json.contains("connected_peer_count"));
    assert!(!json.contains("password copied from clipboard"));
}

#[test]
fn content_type_status_reports_enabled_types() {
    let status = ContentTypeStatus {
        text: true,
        image: false,
        file: true,
    };

    assert_eq!(status.enabled_names(), vec!["text", "file"]);
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-diagnostics --test diagnostics_redaction
```

Expected: FAIL，错误包含 `unresolved import clipplus_diagnostics::redaction::redact_config`。

- [ ] **Step 3: 实现脱敏配置**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/redaction.rs`:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RedactedConfig {
    pub shared_key_configured: bool,
    pub group_id_prefix: String,
    pub device_id_prefix: String,
    pub trusted_peer_count: usize,
    pub paused_peer_count: usize,
}

pub fn redact_config(
    shared_key_configured: bool,
    _raw_key: &str,
    group_id: &str,
    device_id: &str,
    trusted_peer_count: usize,
    paused_peer_count: usize,
) -> RedactedConfig {
    RedactedConfig {
        shared_key_configured,
        group_id_prefix: prefix(group_id),
        device_id_prefix: prefix(device_id),
        trusted_peer_count,
        paused_peer_count,
    }
}

fn prefix(value: &str) -> String {
    value.chars().take(8).collect()
}
```

- [ ] **Step 4: 实现运行状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/status.rs`:

```rust
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContentTypeStatus {
    pub text: bool,
    pub image: bool,
    pub file: bool,
}

impl ContentTypeStatus {
    pub fn enabled_names(&self) -> Vec<&'static str> {
        let mut names = Vec::new();
        if self.text {
            names.push("text");
        }
        if self.image {
            names.push("image");
        }
        if self.file {
            names.push("file");
        }
        names
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuntimeStatus {
    pub app_version: String,
    pub core_version: String,
    pub platform: String,
    pub device_id_prefix: String,
    pub shared_key_configured: bool,
    pub sharing_enabled: bool,
    pub enabled_content_types: ContentTypeStatus,
    pub discovery_status: String,
    pub connected_peer_count: usize,
    pub pending_peer_count: usize,
    pub paused_peer_count: usize,
    pub last_clipboard_event_summary: Option<String>,
    pub last_error: Option<String>,
    pub startup_enabled: bool,
    pub log_level: String,
}

impl RuntimeStatus {
    pub fn new_for_test() -> Self {
        Self {
            app_version: "0.1.0".to_string(),
            core_version: "0.1.0".to_string(),
            platform: "test".to_string(),
            device_id_prefix: "device-1".to_string(),
            shared_key_configured: true,
            sharing_enabled: true,
            enabled_content_types: ContentTypeStatus {
                text: true,
                image: true,
                file: true,
            },
            discovery_status: "running".to_string(),
            connected_peer_count: 1,
            pending_peer_count: 0,
            paused_peer_count: 0,
            last_clipboard_event_summary: Some("text bytes=32".to_string()),
            last_error: None,
            startup_enabled: false,
            log_level: "normal".to_string(),
        }
    }
}
```

- [ ] **Step 5: 实现诊断包导出模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/export.rs`:

```rust
use std::io::{Cursor, Write};

use thiserror::Error;
use zip::write::SimpleFileOptions;

use crate::redaction::RedactedConfig;
use crate::status::RuntimeStatus;

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("json serialization failed: {0}")]
    Json(#[from] serde_json::Error),
    #[error("zip writing failed: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("zip io failed: {0}")]
    Io(#[from] std::io::Error),
}

pub fn export_diagnostics_zip(
    status: &RuntimeStatus,
    config: &RedactedConfig,
    log_text: &str,
) -> Result<Vec<u8>, ExportError> {
    let cursor = Cursor::new(Vec::new());
    let mut zip = zip::ZipWriter::new(cursor);
    let options = SimpleFileOptions::default();

    zip.start_file("runtime-status.json", options)?;
    zip.write_all(serde_json::to_string_pretty(status)?.as_bytes())?;

    zip.start_file("config-redacted.json", options)?;
    zip.write_all(serde_json::to_string_pretty(config)?.as_bytes())?;

    zip.start_file("logs/clipplus.log", options)?;
    zip.write_all(log_text.as_bytes())?;

    let cursor = zip.finish()?;
    Ok(cursor.into_inner())
}
```

- [ ] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-diagnostics --test diagnostics_redaction
```

Expected: PASS，3 个测试通过。

- [ ] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add crates/clipplus-diagnostics
git commit -m "feat: add diagnostics redaction"
```

---

### Task 6: 发现包与局域网发现接口

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/packet.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/udp.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/tests/discovery_packet.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/tests/discovery_packet.rs`:

```rust
use clipplus_discovery::packet::{DiscoveryPacket, PeerCapability};

#[test]
fn discovery_packet_roundtrips_json() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    let json = packet.to_json().unwrap();
    let decoded = DiscoveryPacket::from_json(&json).unwrap();

    assert_eq!(decoded.group_id, "group-a");
    assert_eq!(decoded.device_id, "device-a");
    assert!(decoded.capabilities.contains(&PeerCapability::Text));
}

#[test]
fn group_mismatch_is_rejected() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    assert!(!packet.matches_group("group-b"));
    assert!(packet.matches_group("group-a"));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-discovery --test discovery_packet
```

Expected: FAIL，错误包含 `unresolved import clipplus_discovery::packet::DiscoveryPacket`。

- [ ] **Step 3: 实现发现包**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/packet.rs`:

```rust
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PeerCapability {
    Text,
    Image,
    File,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DiscoveryPacket {
    pub group_id: String,
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub public_key: String,
    pub app_version: String,
    pub capabilities: Vec<PeerCapability>,
}

#[derive(Debug, Error)]
pub enum DiscoveryPacketError {
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

impl DiscoveryPacket {
    pub fn new_for_test(group_id: &str, device_id: &str) -> Self {
        Self {
            group_id: group_id.to_string(),
            device_id: device_id.to_string(),
            device_name: "Test Device".to_string(),
            platform: "test".to_string(),
            public_key: "test-public-key".to_string(),
            app_version: "0.1.0".to_string(),
            capabilities: vec![PeerCapability::Text, PeerCapability::Image, PeerCapability::File],
        }
    }

    pub fn matches_group(&self, group_id: &str) -> bool {
        self.group_id == group_id
    }

    pub fn to_json(&self) -> Result<String, DiscoveryPacketError> {
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, DiscoveryPacketError> {
        Ok(serde_json::from_str(value)?)
    }
}
```

- [ ] **Step 4: 实现 UDP 接口壳**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/udp.rs`:

```rust
use std::net::{Ipv4Addr, SocketAddrV4};

pub const DISCOVERY_PORT: u16 = 47631;
pub const DISCOVERY_BROADCAST: SocketAddrV4 =
    SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), DISCOVERY_PORT);

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoverySocketConfig {
    pub bind_port: u16,
    pub broadcast_addr: SocketAddrV4,
}

impl Default for DiscoverySocketConfig {
    fn default() -> Self {
        Self {
            bind_port: DISCOVERY_PORT,
            broadcast_addr: DISCOVERY_BROADCAST,
        }
    }
}
```

- [ ] **Step 5: 运行测试通过**

Run:

```bash
cargo test -p clipplus-discovery --test discovery_packet
```

Expected: PASS，2 个测试通过。

- [ ] **Step 6: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add crates/clipplus-discovery
git commit -m "feat: add discovery packet model"
```

---

### Task 7: 传输消息、会话状态与文件按需传输模型

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/message.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/session.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/file_transfer.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/tests/message_roundtrip.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-transport/tests/message_roundtrip.rs`:

```rust
use clipplus_transport::file_transfer::{FileTransferRequest, TransferState};
use clipplus_transport::message::{TransportMessage, TransportMessageKind};
use clipplus_transport::session::{HandshakeState, PeerSession};

#[test]
fn transport_message_roundtrips_json() {
    let message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);

    let json = message.to_json().unwrap();
    let decoded = TransportMessage::from_json(&json).unwrap();

    assert_eq!(decoded.kind, TransportMessageKind::TextEvent);
}

#[test]
fn peer_session_requires_trust_before_sync() {
    let session = PeerSession::new("device-a", HandshakeState::PendingApproval);

    assert!(!session.can_sync());
}

#[test]
fn file_transfer_request_has_expiry() {
    let request = FileTransferRequest::new_for_test("transfer-a", 30);

    assert_eq!(request.state, TransferState::Available);
    assert!(!request.is_expired_at_minute(29));
    assert!(request.is_expired_at_minute(31));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-transport --test message_roundtrip
```

Expected: FAIL，错误包含 `unresolved import clipplus_transport::message::TransportMessage`。

- [ ] **Step 3: 实现传输消息**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/message.rs`:

```rust
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum TransportMessageKind {
    Hello,
    ApprovalRequest,
    ApprovalAccepted,
    TextEvent,
    ImageEvent,
    FileListEvent,
    FileChunkRequest,
    FileChunk,
    DiagnosticsPing,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TransportMessage {
    pub message_id: Uuid,
    pub kind: TransportMessageKind,
    pub sender_device_id: String,
    pub payload_json: String,
}

#[derive(Debug, Error)]
pub enum TransportMessageError {
    #[error("json error: {0}")]
    Json(#[from] serde_json::Error),
}

impl TransportMessage {
    pub fn new_for_test(kind: TransportMessageKind) -> Self {
        Self {
            message_id: Uuid::new_v4(),
            kind,
            sender_device_id: "device-a".to_string(),
            payload_json: "{}".to_string(),
        }
    }

    pub fn to_json(&self) -> Result<String, TransportMessageError> {
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, TransportMessageError> {
        Ok(serde_json::from_str(value)?)
    }
}
```

- [ ] **Step 4: 实现会话状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/session.rs`:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandshakeState {
    PendingApproval,
    Trusted,
    Rejected,
    KeyMismatch,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerSession {
    pub device_id: String,
    pub state: HandshakeState,
}

impl PeerSession {
    pub fn new(device_id: impl Into<String>, state: HandshakeState) -> Self {
        Self {
            device_id: device_id.into(),
            state,
        }
    }

    pub fn can_sync(&self) -> bool {
        matches!(self.state, HandshakeState::Trusted)
    }
}
```

- [ ] **Step 5: 实现文件传输请求模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/file_transfer.rs`:

```rust
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Available,
    Active,
    Completed,
    Failed,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferRequest {
    pub transfer_id: String,
    pub expires_after_minutes: u64,
    pub state: TransferState,
}

impl FileTransferRequest {
    pub fn new_for_test(transfer_id: impl Into<String>, expires_after_minutes: u64) -> Self {
        Self {
            transfer_id: transfer_id.into(),
            expires_after_minutes,
            state: TransferState::Available,
        }
    }

    pub fn is_expired_at_minute(&self, elapsed_minutes: u64) -> bool {
        elapsed_minutes > self.expires_after_minutes
    }
}
```

- [ ] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-transport --test message_roundtrip
```

Expected: PASS，3 个测试通过。

- [ ] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add crates/clipplus-transport
git commit -m "feat: add transport message models"
```

---

### Task 8: FFI 状态接口与内存释放约定

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/types.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/api.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/lib.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/tests/ffi_status.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/tests/ffi_status.rs`:

```rust
use std::ffi::CStr;

use clipplus_ffi::api::{clipplus_free_string, clipplus_get_status_json};

#[test]
fn ffi_returns_status_json_and_frees_string() {
    let ptr = unsafe { clipplus_get_status_json() };
    assert!(!ptr.is_null());

    let json = unsafe { CStr::from_ptr(ptr).to_string_lossy().to_string() };
    assert!(json.contains("core_version"));

    unsafe { clipplus_free_string(ptr) };
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-ffi --test ffi_status
```

Expected: FAIL，错误包含 `unresolved import clipplus_ffi::api::clipplus_get_status_json`。

- [ ] **Step 3: 实现 FFI 类型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/types.rs`:

```rust
use std::ffi::CString;
use std::os::raw::c_char;

pub fn string_to_c_ptr(value: String) -> *mut c_char {
    CString::new(value)
        .expect("status json must not contain nul byte")
        .into_raw()
}

pub unsafe fn free_c_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }
    let _ = CString::from_raw(ptr);
}
```

- [ ] **Step 4: 实现 FFI API**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/api.rs`:

```rust
use std::os::raw::c_char;

use clipplus_diagnostics::status::RuntimeStatus;

use crate::types::{free_c_string, string_to_c_ptr};

#[no_mangle]
pub unsafe extern "C" fn clipplus_get_status_json() -> *mut c_char {
    let status = RuntimeStatus::new_for_test();
    let json = serde_json::to_string(&status).expect("runtime status must serialize");
    string_to_c_ptr(json)
}

#[no_mangle]
pub unsafe extern "C" fn clipplus_free_string(ptr: *mut c_char) {
    free_c_string(ptr);
}
```

- [ ] **Step 5: 重新导出 API**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-ffi/src/lib.rs`:

```rust
pub mod api;
pub mod types;

pub use api::{clipplus_free_string, clipplus_get_status_json};
```

- [ ] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-ffi --test ffi_status
```

Expected: PASS，1 个测试通过。

- [ ] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 8: 提交**

```bash
git add crates/clipplus-ffi
git commit -m "feat: expose core status over ffi"
```

---

### Task 9: 开发 CLI 状态和诊断命令

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-cli/src/main.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-cli/tests/cli_status.rs`

- [ ] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-cli/tests/cli_status.rs`:

```rust
use std::process::Command;

#[test]
fn cli_status_outputs_runtime_status_json() {
    let exe = env!("CARGO_BIN_EXE_clipplus-cli");
    let output = Command::new(exe).arg("status").output().unwrap();

    assert!(output.status.success());

    let stdout = String::from_utf8(output.stdout).unwrap();
    assert!(stdout.contains("core_version"));
    assert!(!stdout.contains("raw-secret-key"));
}
```

- [ ] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-cli --test cli_status
```

Expected: FAIL，错误包含 stdout 不包含 `core_version`。

- [ ] **Step 3: 实现 CLI**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-cli/src/main.rs`:

```rust
use anyhow::{bail, Result};
use clipplus_diagnostics::status::RuntimeStatus;

fn main() -> Result<()> {
    let mut args = std::env::args().skip(1);
    match args.next().as_deref() {
        Some("status") => {
            let status = RuntimeStatus::new_for_test();
            println!("{}", serde_json::to_string_pretty(&status)?);
        }
        Some("diagnose") => {
            println!(
                "{}",
                serde_json::json!({
                    "network": "not_started",
                    "clipboard": "not_started",
                    "file_transfer": "not_started"
                })
            );
        }
        Some(command) => bail!("未知命令: {command}"),
        None => bail!("用法: clipplus-cli status | diagnose"),
    }

    Ok(())
}
```

- [ ] **Step 4: 运行测试通过**

Run:

```bash
cargo test -p clipplus-cli --test cli_status
```

Expected: PASS，1 个测试通过。

- [ ] **Step 5: 手动运行状态命令**

Run:

```bash
cargo run -p clipplus-cli -- status
```

Expected: PASS，stdout 为 JSON，包含 `core_version`、`connected_peer_count`、`log_level`。

- [ ] **Step 6: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。

- [ ] **Step 7: 提交**

```bash
git add crates/clipplus-cli
git commit -m "feat: add diagnostic cli"
```

---

### Task 10: macOS SwiftUI 菜单栏壳骨架

**Files:**
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Package.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/MenuBar/MenuBarController.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Settings/SettingsView.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Clipboard/NativeClipboard.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Startup/LoginItemManager.swift`
- Create: `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/CoreBridge/CoreBridge.swift`
- Test: `/Users/cc/proj/ClipPlus/apps/mac/Tests/ClipPlusMacTests/SettingsStateTests.swift`

- [ ] **Step 1: 写 Swift Package**

Create `/Users/cc/proj/ClipPlus/apps/mac/Package.swift`:

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClipPlusMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClipPlusMac", targets: ["ClipPlusMac"])
    ],
    targets: [
        .executableTarget(name: "ClipPlusMac"),
        .testTarget(name: "ClipPlusMacTests", dependencies: ["ClipPlusMac"])
    ]
)
```

- [ ] **Step 2: 写设置状态测试**

Create `/Users/cc/proj/ClipPlus/apps/mac/Tests/ClipPlusMacTests/SettingsStateTests.swift`:

```swift
import XCTest
@testable import ClipPlusMac

final class SettingsStateTests: XCTestCase {
    func testMissingKeyRequiresSetup() {
        let state = SettingsState(sharedKeyConfigured: false, sharingEnabled: true, startupEnabled: false)

        XCTAssertTrue(state.requiresKeySetup)
    }

    func testStartupToggleUpdatesState() {
        var state = SettingsState(sharedKeyConfigured: true, sharingEnabled: true, startupEnabled: false)

        state.startupEnabled = true

        XCTAssertTrue(state.startupEnabled)
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

Run:

```bash
cd apps/mac && swift test
```

Expected: FAIL，错误包含 `cannot find 'SettingsState' in scope`。

- [ ] **Step 4: 实现 mac App 入口和设置状态**

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/App/ClipPlusApp.swift`:

```swift
import SwiftUI

@main
struct ClipPlusApp: App {
    @State private var settingsState = SettingsState(
        sharedKeyConfigured: false,
        sharingEnabled: true,
        startupEnabled: false
    )

    var body: some Scene {
        MenuBarExtra("ClipPlus", systemImage: "doc.on.clipboard") {
            MenuBarController(settingsState: settingsState).view
        }
        Settings {
            SettingsView(state: $settingsState)
        }
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Settings/SettingsView.swift`:

```swift
import SwiftUI

public struct SettingsState: Equatable {
    public var sharedKeyConfigured: Bool
    public var sharingEnabled: Bool
    public var startupEnabled: Bool

    public var requiresKeySetup: Bool {
        !sharedKeyConfigured
    }
}

struct SettingsView: View {
    @Binding var state: SettingsState

    var body: some View {
        Form {
            Section("共享") {
                Toggle("启用剪贴板共享", isOn: $state.sharingEnabled)
                Text(state.sharedKeyConfigured ? "共享 Key：已设置" : "共享 Key：未设置")
                Button("修改 Key") {}
            }
            Section("系统") {
                Toggle("开机自动启动", isOn: $state.startupEnabled)
                Button("导出诊断包") {}
            }
        }
        .padding()
        .frame(width: 420)
    }
}
```

- [ ] **Step 5: 实现菜单栏、剪贴板、启动和 CoreBridge 骨架**

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/MenuBar/MenuBarController.swift`:

```swift
import SwiftUI

struct MenuBarController {
    let settingsState: SettingsState

    var view: some View {
        VStack(alignment: .leading) {
            Text(settingsState.requiresKeySetup ? "状态：共享 Key 未设置" : "状态：准备就绪")
            Toggle("启用剪贴板共享", isOn: .constant(settingsState.sharingEnabled))
            Divider()
            Button("打开设置...") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button("退出 ClipPlus") {
                NSApp.terminate(nil)
            }
        }
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Clipboard/NativeClipboard.swift`:

```swift
import AppKit

struct NativeClipboard {
    func readText() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func writeText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/Startup/LoginItemManager.swift`:

```swift
struct LoginItemManager {
    func isEnabled() -> Bool {
        false
    }

    func setEnabled(_ enabled: Bool) throws {
        _ = enabled
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/mac/Sources/ClipPlusMac/CoreBridge/CoreBridge.swift`:

```swift
import Foundation

struct CoreBridge {
    func statusJSON() -> String {
        "{\"core_version\":\"0.1.0\"}"
    }
}
```

- [ ] **Step 6: 运行 mac 测试通过**

Run:

```bash
cd apps/mac && swift test
```

Expected: PASS，2 个测试通过。

- [ ] **Step 7: 提交**

```bash
git add apps/mac
git commit -m "feat: add mac menu bar shell"
```

---

### Task 11: Windows WPF 托盘壳骨架

**Files:**
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows.sln`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/ClipPlus.Windows.csproj`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/App.xaml`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/App.xaml.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsState.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsWindow.xaml`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsWindow.xaml.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Tray/TrayController.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Clipboard/NativeClipboard.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Startup/StartupManager.cs`
- Create: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/CoreBridge/CoreBridge.cs`
- Test: `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`

- [ ] **Step 1: 创建解决方案和项目**

Run:

```bash
mkdir -p apps/windows
cd apps/windows
dotnet new sln -n ClipPlus.Windows
dotnet new wpf -n ClipPlus.Windows
dotnet new xunit -n ClipPlus.Windows.Tests
dotnet sln add ClipPlus.Windows/ClipPlus.Windows.csproj
dotnet sln add ClipPlus.Windows.Tests/ClipPlus.Windows.Tests.csproj
dotnet add ClipPlus.Windows.Tests/ClipPlus.Windows.Tests.csproj reference ClipPlus.Windows/ClipPlus.Windows.csproj
```

Expected: PASS，生成 WPF App 和 xUnit 测试项目。

- [ ] **Step 2: 修改 WPF 项目启用托盘依赖**

Replace `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/ClipPlus.Windows.csproj`:

```xml
<Project Sdk="Microsoft.NET.Sdk">

  <PropertyGroup>
    <OutputType>WinExe</OutputType>
    <TargetFramework>net8.0-windows</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <UseWPF>true</UseWPF>
    <UseWindowsForms>true</UseWindowsForms>
  </PropertyGroup>

</Project>
```

- [ ] **Step 3: 写设置状态失败测试**

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows.Tests/SettingsStateTests.cs`:

```csharp
using ClipPlus.Windows.Settings;
using Xunit;

namespace ClipPlus.Windows.Tests;

public sealed class SettingsStateTests
{
    [Fact]
    public void MissingKeyRequiresSetup()
    {
        var state = new SettingsState(sharedKeyConfigured: false, sharingEnabled: true, startupEnabled: false);

        Assert.True(state.RequiresKeySetup);
    }

    [Fact]
    public void StartupToggleUpdatesState()
    {
        var state = new SettingsState(sharedKeyConfigured: true, sharingEnabled: true, startupEnabled: false);

        state.StartupEnabled = true;

        Assert.True(state.StartupEnabled);
    }
}
```

- [ ] **Step 4: 运行测试确认失败**

Run:

```bash
cd apps/windows && dotnet test
```

Expected: FAIL，错误包含 `The type or namespace name 'SettingsState' could not be found`。

- [ ] **Step 5: 实现设置状态**

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsState.cs`:

```csharp
namespace ClipPlus.Windows.Settings;

public sealed class SettingsState
{
    public SettingsState(bool sharedKeyConfigured, bool sharingEnabled, bool startupEnabled)
    {
        SharedKeyConfigured = sharedKeyConfigured;
        SharingEnabled = sharingEnabled;
        StartupEnabled = startupEnabled;
    }

    public bool SharedKeyConfigured { get; set; }
    public bool SharingEnabled { get; set; }
    public bool StartupEnabled { get; set; }
    public bool RequiresKeySetup => !SharedKeyConfigured;
}
```

- [ ] **Step 6: 实现托盘和窗口骨架**

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Tray/TrayController.cs`:

```csharp
using System.Windows;
using System.Windows.Forms;
using ClipPlus.Windows.Settings;

namespace ClipPlus.Windows.Tray;

public sealed class TrayController : IDisposable
{
    private readonly NotifyIcon notifyIcon;
    private readonly SettingsState settingsState;

    public TrayController(SettingsState settingsState)
    {
        this.settingsState = settingsState;
        notifyIcon = new NotifyIcon
        {
            Text = "ClipPlus",
            Visible = true
        };
        notifyIcon.ContextMenuStrip = BuildMenu();
    }

    private ContextMenuStrip BuildMenu()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add(settingsState.RequiresKeySetup ? "状态：共享 Key 未设置" : "状态：准备就绪");
        menu.Items.Add("打开设置...", null, (_, _) => new SettingsWindow(settingsState).Show());
        menu.Items.Add("退出 ClipPlus", null, (_, _) => Application.Current.Shutdown());
        return menu;
    }

    public void Dispose()
    {
        notifyIcon.Dispose();
    }
}
```

Replace `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsWindow.xaml`:

```xml
<Window x:Class="ClipPlus.Windows.Settings.SettingsWindow"
        xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="ClipPlus 设置" Height="420" Width="520">
    <StackPanel Margin="16">
        <TextBlock Text="共享" FontWeight="Bold"/>
        <CheckBox Content="启用剪贴板共享" IsChecked="{Binding SharingEnabled}"/>
        <TextBlock Text="共享 Key：已设置或未设置"/>
        <Button Content="修改 Key" Width="120" HorizontalAlignment="Left"/>
        <TextBlock Text="系统" FontWeight="Bold" Margin="0,16,0,0"/>
        <CheckBox Content="开机自动启动" IsChecked="{Binding StartupEnabled}"/>
        <Button Content="导出诊断包" Width="120" HorizontalAlignment="Left"/>
    </StackPanel>
</Window>
```

Replace `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Settings/SettingsWindow.xaml.cs`:

```csharp
using System.Windows;

namespace ClipPlus.Windows.Settings;

public partial class SettingsWindow : Window
{
    public SettingsWindow(SettingsState state)
    {
        InitializeComponent();
        DataContext = state;
    }
}
```

- [ ] **Step 7: 实现剪贴板、启动和 CoreBridge 骨架**

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Clipboard/NativeClipboard.cs`:

```csharp
using System.Windows;

namespace ClipPlus.Windows.Clipboard;

public sealed class NativeClipboard
{
    public string? ReadText()
    {
        return System.Windows.Clipboard.ContainsText() ? System.Windows.Clipboard.GetText() : null;
    }

    public void WriteText(string text)
    {
        System.Windows.Clipboard.SetText(text);
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/Startup/StartupManager.cs`:

```csharp
namespace ClipPlus.Windows.Startup;

public sealed class StartupManager
{
    public bool IsEnabled()
    {
        return false;
    }

    public void SetEnabled(bool enabled)
    {
        _ = enabled;
    }
}
```

Create `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/CoreBridge/CoreBridge.cs`:

```csharp
namespace ClipPlus.Windows.CoreBridge;

public sealed class CoreBridge
{
    public string StatusJson()
    {
        return "{\"core_version\":\"0.1.0\"}";
    }
}
```

Replace `/Users/cc/proj/ClipPlus/apps/windows/ClipPlus.Windows/App.xaml.cs`:

```csharp
using System.Windows;
using ClipPlus.Windows.Settings;
using ClipPlus.Windows.Tray;

namespace ClipPlus.Windows;

public partial class App : Application
{
    private TrayController? trayController;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var settings = new SettingsState(sharedKeyConfigured: false, sharingEnabled: true, startupEnabled: false);
        trayController = new TrayController(settings);

        if (settings.RequiresKeySetup)
        {
            new SettingsWindow(settings).Show();
        }
    }

    protected override void OnExit(ExitEventArgs e)
    {
        trayController?.Dispose();
        base.OnExit(e);
    }
}
```

- [ ] **Step 8: 运行 Windows 测试通过**

Run:

```bash
cd apps/windows && dotnet test
```

Expected: PASS，2 个测试通过。

- [ ] **Step 9: 提交**

```bash
git add apps/windows
git commit -m "feat: add windows tray shell"
```

---

### Task 12: Parallels 端到端测试手册与首轮验证

**Files:**
- Create: `/Users/cc/proj/ClipPlus/scripts/test/parallels-e2e.md`
- Modify: `/Users/cc/proj/ClipPlus/scripts/dev/check.sh`

- [ ] **Step 1: 写 Parallels 测试手册**

Create `/Users/cc/proj/ClipPlus/scripts/test/parallels-e2e.md`:

```markdown
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
```

- [ ] **Step 2: 扩展检查脚本覆盖 Rust、mac、Windows 可用环境**

Replace `/Users/cc/proj/ClipPlus/scripts/dev/check.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace

if command -v swift >/dev/null 2>&1 && [ -f apps/mac/Package.swift ]; then
  (cd apps/mac && swift test)
fi

if command -v dotnet >/dev/null 2>&1 && [ -f apps/windows/ClipPlus.Windows.sln ]; then
  (cd apps/windows && dotnet test)
fi
```

- [ ] **Step 3: 运行全量检查**

Run:

```bash
./scripts/dev/check.sh
```

Expected: PASS。若当前 mac 没有 `dotnet`，脚本跳过 Windows 测试；Windows VM 内需要单独运行 `dotnet test`。

- [ ] **Step 4: 使用 Computer Use 验证 Parallels UI 状态**

Action:

```text
使用 Computer Use 查看 Parallels 是否已打开 Windows VM，并确认是否需要用户手动关闭 Parallels 自带剪贴板共享。
```

Expected: 得到 Windows VM 可用状态。涉及修改 Parallels 共享剪贴板设置或 Windows 防火墙设置时，在动作前向用户确认。

- [ ] **Step 5: 提交**

```bash
git add scripts/dev/check.sh scripts/test/parallels-e2e.md
git commit -m "test: add parallels e2e checklist"
```

---

## 自查清单

Spec 覆盖：

- Rust core 模型：Task 1、Task 2、Task 4。
- 共享 Key 和设备身份：Task 3。
- 首次确认和信任状态：Task 3、Task 7。
- 文字、图片、文件事件模型：Task 2、Task 7。
- 防回环：Task 4。
- 日志、脱敏、诊断包：Task 5。
- 局域网发现：Task 6。
- 传输和文件按需传输模型：Task 7。
- FFI：Task 8。
- CLI：Task 9。
- mac 菜单栏与设置：Task 10。
- Windows 托盘与设置：Task 11。
- 开机启动骨架：Task 10、Task 11。
- Parallels 测试：Task 12。

执行约束：

- 所有计划内容使用中文说明。
- 不使用 HTML、Electron、Tauri 或 WebView。
- 每个任务都有测试、验证命令和提交点。
- 日志和诊断设计不记录原始共享 Key、剪贴板正文、图片内容和文件内容。

风险分解：

- Windows 原生延迟文件粘贴可能需要较多 Shell 互操作。本计划先完成传输模型和降级接收路径，原生 Finder/Explorer 延迟粘贴在后续专项计划中扩展。
- macOS Login Item 和 Windows HKCU Run 首版先做接口骨架，真实系统写入在后续实现任务中用平台测试补齐。
- 局域网加密握手首轮先完成身份、消息和会话模型，实际加密会话在传输专项任务中继续细化。

## 执行方式

Plan complete and saved to `docs/superpowers/plans/2026-06-09-clipplus-cross-device-clipboard.md`. Two execution options:

1. **Subagent-Driven (recommended)** - 我按任务派发独立子代理，每个任务后 review，适合这个多平台项目。
2. **Inline Execution** - 在当前会话中使用 executing-plans 按任务批量执行，并在关键节点停下来检查。

请选择执行方式。
