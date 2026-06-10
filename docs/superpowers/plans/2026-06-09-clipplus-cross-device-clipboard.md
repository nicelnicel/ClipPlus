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

- [x] **Step 1: 扩展失败测试**

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

    guard.mark_remote_write(&event);

    assert!(guard.should_ignore_local_change(&event));
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

质量审查后继续补充以下回归测试：

- `default_policy_allows_text_publish`
- `policy_blocks_text_when_text_sync_is_disabled`
- `policy_blocks_image_when_image_sync_is_disabled`
- `policy_blocks_image_when_image_is_too_large`
- `policy_blocks_file_list_when_file_sync_is_disabled`
- `remote_write_guard_matches_same_payload_with_new_event_id`
- `remote_write_lru_refreshes_repeated_payload`
- `remote_write_and_processed_caches_do_not_pollute_each_other`
- `processed_lru_refreshes_repeated_event_id`
- `cloned_service_shares_loop_guard_state`
- `service_policy_uses_updated_settings_snapshot`

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

初始预期：FAIL，错误包含 `unresolved import clipplus_core::sync::LoopGuard`。

质量修复阶段新增事件级 API 测试后再次 RED：旧实现只接受 `Uuid`，新增测试触发 `E0308 mismatched types`；`CoreService` 缺少领域方法时触发 `E0599 no method named mark_remote_write / should_ignore_local_change / update_settings`。

- [x] **Step 3: 实现同步策略**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/sync.rs`:

```rust
use std::collections::{hash_map::DefaultHasher, VecDeque};
use std::hash::{Hash, Hasher};

use uuid::Uuid;

use crate::config::SyncSettings;
use crate::event::{ClipboardEvent, ClipboardPayload, ImageFormat};

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
    recent_remote_writes: VecDeque<RemoteWriteRecord>,
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
    pub fn mark_remote_write(&mut self, event: &ClipboardEvent) {
        let record = RemoteWriteRecord::from_event(event);

        Self::push_lru_by(
            &mut self.recent_remote_writes,
            self.capacity,
            record,
            |entry| entry.event_id == record.event_id || entry.payload == record.payload,
        );
    }

    pub fn should_ignore_local_change(&self, event: &ClipboardEvent) -> bool {
        let payload = PayloadFingerprint::from_event(event);

        self.recent_remote_writes
            .iter()
            .any(|entry| entry.event_id == event.event_id || entry.payload == payload)
    }

    pub fn mark_processed(&mut self, event_id: Uuid) {
        Self::push_lru_by(
            &mut self.recent_processed,
            self.capacity,
            event_id,
            |entry| *entry == event_id,
        );
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.recent_processed.contains(&event_id)
    }

    fn push_lru_by<T>(
        queue: &mut VecDeque<T>,
        capacity: usize,
        item: T,
        matches: impl Fn(&T) -> bool,
    ) {
        if let Some(position) = queue.iter().position(matches) {
            queue.remove(position);
        }

        queue.push_back(item);
        while queue.len() > capacity {
            queue.pop_front();
        }
    }
}
```

实际落地还包含：

- `RemoteWriteRecord { event_id, payload: PayloadFingerprint }`
- `PayloadFingerprint(u64)` 使用 `DefaultHasher` 做进程内短期 payload 指纹，不保存原始剪贴板文本。
- 文本指纹包含 payload variant、text、byte_size。
- 图片指纹包含 payload variant、format、byte_size、width、height、content_hash。
- 文件列表指纹排除 `transfer_id` / `file_id`，基于文件数量、name、size、modified_at、content_hash、source_relative_path，并排序后计算，避免同一批文件因传输 UUID 或顺序变化误判。
- LRU 重复命中会移除旧位置后 `push_back`，不会退化成 FIFO。

- [x] **Step 4: 实现 core 服务壳状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-core/src/service.rs`:

```rust
use std::sync::{Arc, Mutex, MutexGuard};

use crate::config::SyncSettings;
use crate::event::ClipboardEvent;
use crate::sync::{LoopGuard, SyncPolicy};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub struct CoreService {
    state: Arc<Mutex<CoreServiceState>>,
}

#[derive(Debug)]
struct CoreServiceState {
    settings: SyncSettings,
    loop_guard: LoopGuard,
}

impl CoreService {
    pub fn new(settings: SyncSettings) -> Self {
        Self {
            state: Arc::new(Mutex::new(CoreServiceState {
                settings,
                loop_guard: LoopGuard::default(),
            })),
        }
    }

    pub fn policy(&self) -> SyncPolicy {
        SyncPolicy::new(self.lock_state().settings.clone())
    }

    pub fn loop_guard(&self) -> LoopGuard {
        self.lock_state().loop_guard.clone()
    }

    pub fn mark_remote_write(&self, event: &ClipboardEvent) {
        self.lock_state().loop_guard.mark_remote_write(event);
    }

    pub fn should_ignore_local_change(&self, event: &ClipboardEvent) -> bool {
        self.lock_state().loop_guard.should_ignore_local_change(event)
    }

    pub fn mark_processed(&self, event_id: Uuid) {
        self.lock_state().loop_guard.mark_processed(event_id);
    }

    pub fn has_processed(&self, event_id: Uuid) -> bool {
        self.lock_state().loop_guard.has_processed(event_id)
    }

    pub fn update_settings(&self, settings: SyncSettings) {
        self.lock_state().settings = settings;
    }

    fn lock_state(&self) -> MutexGuard<'_, CoreServiceState> {
        self.state
            .lock()
            .expect("core service state mutex poisoned")
    }
}
```

`CoreService` 使用 `Arc<Mutex<CoreServiceState>>`，`Clone` 后共享 settings 和 loop guard 状态，避免网络接收路径和剪贴板监听路径持有不同 clone 时状态分裂。

- [x] **Step 5: 运行测试通过**

Run:

```bash
cargo test -p clipplus-core --test sync_policy
```

预期：PASS，当前 `sync_policy` 30 个测试全部通过。

- [x] **Step 6: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

预期：PASS。

- [x] **Step 7: 提交**

```bash
git add crates/clipplus-core
git commit -m "feat: add sync policy and loop guard"
```

质量修复提交：

```bash
git commit -m "fix: harden loop guard state handling"
```

**已接受提交：**

- `1222f5482bc25db515758ee5322368e33d583607` `feat: add sync policy and loop guard`
- `9cb0f64a316b0ba0b521012a0a9464b22e0894d6` `fix: harden loop guard state handling`

**审查状态：**

- 规格审查：通过。
- 代码质量审查：第一轮发现只按 `event_id` 做回环保护、`CoreService` 状态克隆分裂、LRU 语义和测试覆盖问题；已修复。
- 代码质量复审：通过，无 Critical/Important/Minor。

---

### Task 5: 诊断状态、日志脱敏和诊断包导出

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/status.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/redaction.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/export.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/tests/diagnostics_redaction.rs`

- [x] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/tests/diagnostics_redaction.rs`:

```rust
use clipplus_diagnostics::redaction::{redact_config, redact_sensitive_text};
use clipplus_diagnostics::status::{
    ClipboardContentKind, ClipboardEventSummary, ContentTypeStatus, RuntimeStatus,
    SafeDiagnosticMessage,
};

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
fn runtime_status_serializes_without_clipboard_content_or_error_secrets() {
    let mut status = RuntimeStatus::new_for_test();
    status.last_error = Some(SafeDiagnosticMessage::new("failed token=runtime-secret"));
    let json = serde_json::to_string(&status).unwrap();

    assert!(json.contains("connected_peer_count"));
    assert!(json.contains("last_clipboard_event_summary"));
    assert!(json.contains("\"content_kind\":\"Text\""));
    assert!(json.contains("\"byte_count\":32"));
    assert!(!json.contains("password copied from clipboard"));
    assert!(!json.contains("runtime-secret"));
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

质量审查后继续补充以下回归测试：

- `redacted_config_uses_eight_character_prefixes_for_long_ids`
- `clipboard_event_summary_constructors_do_not_accept_raw_content`
- `sensitive_text_redaction_handles_common_secret_formats`
- `sensitive_text_redaction_handles_escaped_quotes_in_quoted_values`
- `safe_diagnostic_message_redacts_escaped_quote_secrets`
- `diagnostics_zip_contains_stable_redacted_entries`

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-diagnostics --test diagnostics_redaction
```

初始预期：FAIL，错误包含 `unresolved import clipplus_diagnostics::redaction::redact_config`。

质量修复阶段新增结构化摘要和公共脱敏函数测试后再次 RED：缺少 `redact_sensitive_text`、`ClipboardContentKind`、`ClipboardEventSummary`、`SafeDiagnosticMessage`；转义引号修复前，`abc\"def` 形式的 quoted secret 会残留后半段。

- [x] **Step 3: 实现脱敏配置**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/redaction.rs`:

```rust
use serde::{Deserialize, Serialize};

pub const REDACTED_ID_PREFIX_CHARS: usize = 8;

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
    value.chars().take(REDACTED_ID_PREFIX_CHARS).collect()
}
```

实际落地还包含 `redact_sensitive_text(text: &str) -> String`：

- 统一供 `export.rs` 和 `status.rs` 使用。
- 支持大小写不敏感字段名 `key`、`shared_key`、`token`。
- 支持 `=` / `:`、分隔符周围空白、单双引号、JSON 字段、URL/query 参数。
- 未引用值按空白、逗号、分号、`&`、引号结束。
- quoted value 会识别反斜杠转义，不会把 `\"` 当成结束引号，避免 `abc\"def` 泄漏后半段。

- [x] **Step 4: 实现运行状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/status.rs`:

```rust
use serde::{Deserialize, Deserializer, Serialize};

use crate::redaction::redact_sensitive_text;

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
pub enum ClipboardContentKind {
    Text,
    Image,
    FileList,
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ClipboardEventSummary {
    pub content_kind: ClipboardContentKind,
    pub byte_count: usize,
    pub item_count: Option<usize>,
    pub source_device_id_prefix: Option<String>,
}

impl ClipboardEventSummary {
    pub fn text(byte_count: usize) -> Self { /* ... */ }
    pub fn image(byte_count: usize) -> Self { /* ... */ }
    pub fn file_list(item_count: usize) -> Self { /* ... */ }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SafeDiagnosticMessage {
    message: String,
}

impl SafeDiagnosticMessage {
    pub fn new(message: impl AsRef<str>) -> Self {
        Self {
            message: redact_sensitive_text(message.as_ref()),
        }
    }

    pub fn as_str(&self) -> &str {
        &self.message
    }
}

impl<'de> Deserialize<'de> for SafeDiagnosticMessage {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct RawMessage {
            message: String,
        }

        let raw = RawMessage::deserialize(deserializer)?;
        Ok(Self::new(raw.message))
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
    pub last_clipboard_event_summary: Option<ClipboardEventSummary>,
    pub last_error: Option<SafeDiagnosticMessage>,
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
            last_clipboard_event_summary: Some(ClipboardEventSummary::text(32)),
            last_error: None,
            startup_enabled: false,
            log_level: "normal".to_string(),
        }
    }
}
```

`RuntimeStatus` 保留 JSON 字段名 `last_clipboard_event_summary` 和 `last_error`，但字段类型已从自由字符串收窄为结构化安全摘要和会自动脱敏的安全消息，避免调用方直接放入真实剪贴板内容或 secret。

- [x] **Step 5: 实现诊断包导出模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-diagnostics/src/export.rs`:

```rust
use std::io::{Cursor, Write};

use thiserror::Error;
use zip::write::SimpleFileOptions;

use crate::redaction::{redact_sensitive_text, RedactedConfig};
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
    zip.write_all(redact_sensitive_text(log_text).as_bytes())?;

    let cursor = zip.finish()?;
    Ok(cursor.into_inner())
}
```

诊断包测试会打开 zip 并精确校验 3 个稳定条目名：

- `runtime-status.json`
- `config-redacted.json`
- `logs/clipplus.log`

测试同时解析 status/config JSON，确认 raw key、完整 group id、完整 device id 不进入诊断包。

- [x] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-diagnostics --test diagnostics_redaction
```

预期：PASS，当前 9 个测试通过。

- [x] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

预期：PASS。

- [x] **Step 8: 提交**

```bash
git add crates/clipplus-diagnostics
git commit -m "feat: add diagnostics redaction"
```

质量修复提交：

```bash
git commit -m "fix: harden diagnostics sanitization"
git commit -m "fix: handle escaped diagnostic secrets"
```

**已接受提交：**

- `27bb63fedad2b74c0cc367d7ce042f96b69d8037` `feat: add diagnostics redaction`
- `ec5b7eb9927d28dc250971f30b33ffc41025e07f` `fix: harden diagnostics sanitization`
- `c88a8e2456e3b9199884460ef112ef43d3583e9a` `fix: handle escaped diagnostic secrets`

**审查状态：**

- 规格审查：通过。
- 代码质量审查：第一轮发现日志脱敏格式覆盖不足、运行状态自由字符串和 zip 条目测试缺口；已修复。
- 代码质量复审：第二轮发现 quoted/JSON 字符串中 `\"` 转义会导致 secret 后半段泄漏；已修复。
- 最终代码质量复审：通过。仅保留非阻塞建议：后续可收紧 `ClipboardEventSummary::source_device_id_prefix` 的写入路径，统一截断完整设备 ID。

---

### Task 6: 发现包与局域网发现接口

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/packet.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/udp.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/tests/discovery_packet.rs`

- [x] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/tests/discovery_packet.rs`:

```rust
use clipplus_discovery::packet::{DiscoveryPacket, DiscoveryPacketError, PeerCapability};
use clipplus_discovery::udp::{DiscoverySocketConfig, DISCOVERY_BROADCAST, DISCOVERY_PORT};

#[test]
fn discovery_packet_roundtrips_json() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    let json = packet.to_json().unwrap();
    let decoded = DiscoveryPacket::from_json(&json).unwrap();

    assert_eq!(decoded.group_id, "group-a");
    assert_eq!(decoded.device_id, "device-a");
    assert_eq!(
        decoded.capabilities,
        vec![
            PeerCapability::Text,
            PeerCapability::Image,
            PeerCapability::File,
        ]
    );
}

#[test]
fn group_mismatch_is_rejected() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    assert!(!packet.matches_group("group-b"));
    assert!(packet.matches_group("group-a"));
}
```

质量审查后继续补充以下协议契约测试：

- `packet_json_uses_stable_wire_values`
- `unknown_capability_is_preserved`
- `empty_group_never_matches`
- `from_json_rejects_empty_group_or_device`
- `malformed_json_returns_json_error`
- `unknown_fields_are_ignored_for_forward_compatibility`
- `default_udp_config_uses_stable_discovery_endpoint`

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-discovery --test discovery_packet
```

初始预期：FAIL，错误包含 `unresolved import clipplus_discovery::packet::DiscoveryPacket`。

质量修复阶段新增协议测试后再次 RED：缺少 `PeerCapability::Unknown` 和 `DiscoveryPacketError::InvalidField` 等接口。

- [x] **Step 3: 实现发现包**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-discovery/src/packet.rs`:

```rust
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PeerCapability {
    Text,
    Image,
    File,
    Unknown(String),
}

impl Serialize for PeerCapability {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let value = match self {
            Self::Text => "text",
            Self::Image => "image",
            Self::File => "file",
            Self::Unknown(value) => value,
        };
        serializer.serialize_str(value)
    }
}

impl<'de> Deserialize<'de> for PeerCapability {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        let value = String::deserialize(deserializer)?;
        Ok(match value.as_str() {
            "text" => Self::Text,
            "image" => Self::Image,
            "file" => Self::File,
            _ => Self::Unknown(value),
        })
    }
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
    #[error("invalid discovery packet field: {0}")]
    InvalidField(&'static str),
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
        !self.group_id.trim().is_empty()
            && !group_id.trim().is_empty()
            && self.group_id == group_id
    }

    pub fn to_json(&self) -> Result<String, DiscoveryPacketError> {
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, DiscoveryPacketError> {
        let packet = serde_json::from_str::<Self>(value)?;
        packet.validate()?;
        Ok(packet)
    }

    pub fn validate(&self) -> Result<(), DiscoveryPacketError> {
        if self.group_id.trim().is_empty() {
            return Err(DiscoveryPacketError::InvalidField("group_id"));
        }
        if self.device_id.trim().is_empty() {
            return Err(DiscoveryPacketError::InvalidField("device_id"));
        }
        Ok(())
    }
}
```

实际落地的 discovery JSON wire contract：

- capabilities 固定序列化为 `["text", "image", "file"]`，不依赖 Rust enum variant 名。
- 未知 capability 会保留为 `PeerCapability::Unknown(String)`，用于后续手机端或新版本前向兼容。
- `from_json` 允许未知字段，便于新旧版本发现包兼容。
- `from_json` 拒绝空白 `group_id` / `device_id`。
- `matches_group` 在本地 group 或包内 group 为空白时返回 false，其余情况仍使用派生后 group id 精确比较。
- 测试解析 JSON object 并断言字段集合精确为 `group_id/device_id/device_name/platform/public_key/app_version/capabilities`，同时禁止 `raw_key/shared_key/verifier/private_key` 字段出现在发现包中。

- [x] **Step 4: 实现 UDP 接口壳**

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

- [x] **Step 5: 运行测试通过**

Run:

```bash
cargo test -p clipplus-discovery --test discovery_packet
```

预期：PASS，当前 9 个测试通过。

- [x] **Step 6: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

预期：PASS。

- [x] **Step 7: 提交**

```bash
git add crates/clipplus-discovery
git commit -m "feat: add discovery packet model"
```

质量修复提交：

```bash
git commit -m "fix: harden discovery packet contract"
```

**已接受提交：**

- `ccc68f195c419cc298fea398e87e76a3dcbc47b5` `feat: add discovery packet model`
- `a19925d7a5b6be5d4401d472ed9cf56ce7a5fb2a` `fix: harden discovery packet contract`

**审查状态：**

- 规格审查：通过。
- 代码质量审查：第一轮发现 capability wire contract 依赖 Serde 默认 Rust variant、未知能力不兼容、空 group/device 边界和测试覆盖不足；已修复。
- 代码质量复审：通过。仅保留非阻塞建议：后续真实发送路径可以让 `to_json()` 调用 `validate()` 或引入受校验构造器，进一步收紧本端生成包边界。

---

### Task 7: 传输消息、会话状态与文件按需传输模型

**Files:**
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/message.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/session.rs`
- Modify: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/file_transfer.rs`
- Test: `/Users/cc/proj/ClipPlus/crates/clipplus-transport/tests/message_roundtrip.rs`

- [x] **Step 1: 写失败测试**

Create `/Users/cc/proj/ClipPlus/crates/clipplus-transport/tests/message_roundtrip.rs`:

```rust
use clipplus_transport::file_transfer::{FileTransferError, FileTransferRequest, TransferState};
use clipplus_transport::message::{TransportMessage, TransportMessageError, TransportMessageKind};
use clipplus_transport::session::{HandshakeState, PeerSession, SessionError};

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
    assert!(!request.is_expired_at_minute(30));
    assert!(request.is_expired_at_minute(31));
}
```

质量审查后继续补充以下回归测试：

- `transport_message_kind_uses_snake_case_wire_value`
- `transport_message_rejects_invalid_json`
- `transport_message_rejects_empty_sender_device_id`
- `transport_message_rejects_non_json_payload_json`
- `transport_message_to_json_rejects_empty_sender_device_id`
- `transport_message_to_json_rejects_non_json_payload_json`
- `transport_message_unknown_kind_is_rejected`
- `peer_session_allows_sync_only_when_trusted`
- `peer_session_rejects_blank_device_id`
- `peer_session_trims_device_id_on_new`
- `peer_session_can_sync_defends_against_blank_public_device_id`
- `file_transfer_request_supports_u64_expiry_minutes`
- `file_transfer_request_rejects_blank_transfer_id`
- `file_transfer_request_trims_transfer_id_on_new`

- [x] **Step 2: 运行测试确认失败**

Run:

```bash
cargo test -p clipplus-transport --test message_roundtrip
```

初始预期：FAIL，错误包含 `unresolved import clipplus_transport::message::TransportMessage`。

规格修复阶段再次 RED：新增超过 `u32::MAX` 的过期分钟数测试后，当前 API 编译失败，错误为 `expected u32, found u64`。质量修复阶段再次 RED：缺少 `TransportMessageError::InvalidField`、`PeerSession::try_new`、`SessionError`、`FileTransferRequest::new`、`FileTransferError` 等校验型接口。

- [x] **Step 3: 实现传输消息**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/message.rs`:

```rust
use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
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
    #[error("invalid transport message field: {0}")]
    InvalidField(&'static str),
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
        self.validate()?;
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, TransportMessageError> {
        let message = serde_json::from_str::<Self>(value)?;
        message.validate()?;
        Ok(message)
    }

    fn validate(&self) -> Result<(), TransportMessageError> {
        if self.sender_device_id.trim().is_empty() {
            return Err(TransportMessageError::InvalidField("sender_device_id"));
        }

        if serde_json::from_str::<serde_json::Value>(&self.payload_json).is_err() {
            return Err(TransportMessageError::InvalidField("payload_json"));
        }

        Ok(())
    }
}
```

实际落地还包含：

- `TransportMessageKind` wire 值固定为 snake_case，例如 `text_event`。
- `from_json` 和 `to_json` 共用校验逻辑，发送和接收都会拒绝空白 `sender_device_id` 与非 JSON 的 `payload_json`。
- 字段校验错误使用 `TransportMessageError::InvalidField(&'static str)`，malformed JSON 和未知 kind 仍作为 JSON 反序列化错误处理；未知 kind 当前严格拒绝，这是有意的 message action contract。

- [x] **Step 4: 实现会话状态**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/session.rs`:

```rust
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandshakeState {
    PendingApproval,
    Trusted,
    Rejected,
    KeyMismatch,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SessionError {
    #[error("invalid peer session field: {0}")]
    InvalidField(&'static str),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerSession {
    pub device_id: String,
    pub state: HandshakeState,
}

impl PeerSession {
    pub fn new(device_id: impl Into<String>, state: HandshakeState) -> Self {
        Self::try_new(device_id, state).expect("valid peer session device id")
    }

    pub fn try_new(
        device_id: impl Into<String>,
        state: HandshakeState,
    ) -> Result<Self, SessionError> {
        let device_id = device_id.into();
        let device_id = device_id.trim();
        if device_id.is_empty() {
            return Err(SessionError::InvalidField("device_id"));
        }

        Ok(Self {
            device_id: device_id.to_string(),
            state,
        })
    }

    pub fn can_sync(&self) -> bool {
        self.state == HandshakeState::Trusted && !self.device_id.trim().is_empty()
    }
}
```

`PeerSession::try_new` 是面向外部输入的安全构造器；`new` 保持原计划测试兼容并委托 `try_new`。`can_sync` 额外防御手动构造 public 字段造成的空身份 Trusted session。

- [x] **Step 5: 实现文件传输请求模型**

Replace `/Users/cc/proj/ClipPlus/crates/clipplus-transport/src/file_transfer.rs`:

```rust
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Available,
    Active,
    Completed,
    Failed,
    Expired,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum FileTransferError {
    #[error("invalid file transfer field: {0}")]
    InvalidField(&'static str),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferRequest {
    pub transfer_id: String,
    pub expires_after_minutes: u64,
    pub state: TransferState,
}

impl FileTransferRequest {
    pub fn new(
        transfer_id: impl Into<String>,
        expires_after_minutes: u64,
    ) -> Result<Self, FileTransferError> {
        let transfer_id = transfer_id.into();
        let transfer_id = transfer_id.trim();
        if transfer_id.is_empty() {
            return Err(FileTransferError::InvalidField("transfer_id"));
        }

        Ok(Self {
            transfer_id: transfer_id.to_string(),
            expires_after_minutes,
            state: TransferState::Available,
        })
    }

    pub fn new_for_test(transfer_id: impl Into<String>, expires_after_minutes: u64) -> Self {
        Self::new(transfer_id, expires_after_minutes).expect("valid file transfer id")
    }

    pub fn is_expired_at_minute(&self, elapsed_minutes: u64) -> bool {
        elapsed_minutes > self.expires_after_minutes
    }
}
```

文件传输请求现在提供校验型生产构造器 `new`，trim 后拒绝空白 transfer id；`new_for_test` 委托 `new` 保持测试便捷性。

- [x] **Step 6: 运行测试通过**

Run:

```bash
cargo test -p clipplus-transport --test message_roundtrip
```

预期：PASS，当前 17 个测试通过。

- [x] **Step 7: 运行 workspace 检查**

Run:

```bash
./scripts/dev/check.sh
```

预期：PASS。

- [x] **Step 8: 提交**

```bash
git add crates/clipplus-transport
git commit -m "feat: add transport message models"
```

质量修复提交：

```bash
git commit -m "fix: use u64 transfer expiry"
git commit -m "fix: validate transport model invariants"
```

**已接受提交：**

- `4008b71104cda02fde3b4246a1f9722ab35fbd88` `feat: add transport message models`
- `e23459867e38e1d7ae185f1a417df8fecbab3faa` `fix: use u64 transfer expiry`
- `43326b06e7acd31a7d36ac77a0f5d80d9906fe5d` `fix: validate transport model invariants`

**审查状态：**

- 规格审查：第一轮发现文件传输过期分钟数使用 `u32`，与计划 `u64` 不一致；已修复。
- 规格复审：通过。
- 代码质量审查：第一轮发现发送侧 `to_json` 不校验、可信空身份 session、空 transfer id 请求、错误类型不结构化和未知 kind contract 缺测试；已修复。
- 代码质量复审：通过。仅保留非阻塞建议：后续 FFI/CLI 边界应优先使用 `try_new`/`new` 校验型接口，真实 payload 落地前再决定 `payload_json` 是否升级为 typed payload 或 `serde_json::Value`。

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

**已接受提交：**

- `3d291f19f865260e045709c2b2ac639ee0d6f975` `feat: expose core status over ffi`
- `143fd71ff4d8cbb5c38423cf149dd663b0f9934c` `fix: document ffi string ownership`

**审查状态：**

- 规格审查：通过。`clipplus_get_status_json`、`clipplus_free_string`、crate root re-export 和 FFI 状态 JSON 测试均覆盖计划要求。
- 代码质量审查：第一轮发现 Safety 文档没有明确 `*mut c_char` 对调用方只读、必须原样传回释放，且 root re-export 的 `clipplus_free_string` 覆盖不足；已修复。
- 代码质量复审：通过。Safety 文档已明确 `*mut` 仅用于所有权释放，不代表可写；调用方不得修改内容、提前插入 NUL、改变长度或修改终止 NUL。测试 helper 已通过 crate root re-export 的释放函数释放非空状态字符串，并增加 root re-export null free 覆盖。

**验证记录：**

- `cargo test -p clipplus-ffi --test ffi_status`：通过，5/5。
- `cargo clippy -p clipplus-ffi --all-targets -- -D warnings`：通过。
- `RUSTDOCFLAGS='-D warnings' cargo doc -p clipplus-ffi --no-deps`：通过。
- `git diff --check`：通过。
- `./scripts/dev/check.sh`：通过。

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

**已接受提交：**

- `05b7127263149bdf3c2586dd858c1a6e186161d2` `feat: add diagnostic cli`

**审查状态：**

- 规格审查：通过。提交范围仅包含 `clipplus-cli` 主程序和集成测试；`status`、`diagnose`、未知命令、无命令行为均覆盖计划要求。
- 代码质量审查：通过。当前实现作为首版开发调试 CLI 可接受，没有引入完整 CLI 框架，没有输出原始剪贴板内容、完整设备 ID、共享 Key、token、环境变量或路径等敏感信息。
- 非阻断建议：后续可把 `status` 测试升级为 JSON 字段级断言；可对多余参数返回用法错误；真实运行状态接入后应替换 `RuntimeStatus::new_for_test()`。

**验证记录：**

- `cargo test -p clipplus-cli --test cli_status`：通过，4/4。
- `cargo run -p clipplus-cli -- status`：通过，stdout 为 pretty JSON，包含 `core_version`、`connected_peer_count`、`log_level`。
- `cargo run -p clipplus-cli -- diagnose`：通过，stdout 为 JSON，三项状态均为 `not_started`。
- `cargo clippy -p clipplus-cli --all-targets -- -D warnings`：通过。
- `git diff --check`：通过。
- `./scripts/dev/check.sh`：通过。

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

**已接受提交：**

- `c5f52db39deeb71a6ed8f168c217ede4f31a5972` `feat: add mac menu bar shell`
- `d9e1e9a5f65981a162d579254951fff2439229f8` `fix: align mac settings defaults`
- `4e90495` `fix: make mac menu settings accessible`

**审查状态：**

- 规格审查：第一轮发现 `requiresKeySetup` 错误依赖 `sharingEnabled`，以及 `SettingsState()` 默认 `sharingEnabled` 与计划初始状态不一致；已修复。
- 规格复审：通过。`requiresKeySetup` 现为 `!sharedKeyConfigured`；默认状态为 `sharedKeyConfigured: false, sharingEnabled: true, startupEnabled: false`；补充了默认值和共享关闭但未设置 Key 的测试。
- 代码质量审查：通过。`MenuBarExtra` + `Settings` 的状态绑定、macOS 13 兼容设置入口、剪贴板/开机启动/CoreBridge 骨架均符合首版任务边界。
- 运行验证修复：首轮启动验证发现 pull-down menu 内“打开设置”无法在锁屏/自动化路径中调出窗口；已改为 `.menuBarExtraStyle(.window)`，点击菜单栏图标直接展示设置面板，并保留独立设置窗口入口。

**验证记录：**

- `cd apps/mac && swift test`：通过，4/4。
- `cd apps/mac && swift build`：通过。
- `git diff --check`：通过。
- `./scripts/dev/check.sh`：通过。

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

**已接受提交：**

- `2b7c7d2a2b7dd9ae6c2844cc508f422a2fa32f5f` `feat: add windows tray shell`

**审查状态：**

- 规格审查：通过。解决方案、WPF app、xUnit 测试、托盘、设置窗口、剪贴板、开机启动和 CoreBridge 骨架文件均覆盖计划要求。
- 代码质量审查：通过。WPF/WinForms 托盘互操作配置、`NotifyIcon` 生命周期、WPF `Application` 与 WinForms 命名空间冲突处理、项目引用结构和设置状态测试均未发现静态阻塞问题。
- 运行复验修复：Parallels Windows 首次真实编译发现 `App.xaml.cs` 中 `Application` 在 WPF 和 WinForms 命名空间之间存在歧义；已改为显式继承 `System.Windows.Application`。

**验证记录：**

- `git diff --check HEAD~1..HEAD`：通过。
- `./scripts/dev/check.sh`：通过。
- `dotnet test apps/windows/ClipPlus.Windows.sln`：已在 Parallels Windows VM 中使用 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 运行，通过 2/2。
- Windows 桌面启动验证：已在 Parallels Windows VM 的当前桌面用户会话中启动 `ClipPlus.Windows.dll`；设置窗口可见，系统托盘展开区可见 ClipPlus 托盘图标。

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

**已接受提交：**

- `a41a496ee5ff1c3f60de6bda5478aa30d5da108f` `test: add parallels e2e checklist`

**审查状态：**

- 规格审查：通过。Parallels 测试手册包含测试目标、前置条件、步骤和失败定位；覆盖 macOS 检查、CLI status、mac Swift test、Windows `dotnet test`、菜单栏/托盘确认、同 Key、设备允许、双向文字复制和诊断包不含 Key。
- 代码质量审查：通过。`scripts/dev/check.sh` 保持 Rust 检查，并在 Swift/dotnet 环境可用且对应项目存在时条件运行 macOS/Windows 测试；本机无 `dotnet` 时正确跳过 Windows 分支。手册没有引导用户直接修改防火墙规则，并明确诊断包不得包含 `clipplus-test-key`。

**验证记录：**

- `./scripts/dev/check.sh`：通过；包含 Rust fmt/clippy/test 和 macOS Swift test；Windows dotnet 分支因本机无 `dotnet` 被跳过。
- `cargo run -p clipplus-cli -- status`：通过，输出包含 `core_version`。
- `cd apps/mac && swift test`：通过，4/4。
- `git diff --check HEAD~1..HEAD`：通过。

**首轮运行验证状态：**

- macOS：`ClipPlusMac` 可构建并以临时 `.app` 方式启动；进程存在。菜单栏状态项可被 Accessibility 识别。运行验证过程中发现宿主机处于锁屏界面，无法完成最终视觉确认。
- Parallels Windows：`prlctl` 能识别 `Windows 11` VM，但 `prlctl start "Windows 11"` 返回成功后 VM 仍显示 `stopped`，IP 为空；无法进入 Windows 桌面执行 `dotnet test` 或托盘验证。
- Parallels 配置：当前 `Shared clipboard mode: on`。真正剪贴板同步验证前，需要用户确认是否关闭 Parallels 自带剪贴板共享。

**2026-06-10 复验状态：**

- 全量脚本：`./scripts/dev/check.sh` 通过；Rust fmt/clippy/test、Rust doc tests 和 macOS Swift test 均通过，Windows dotnet 分支因 macOS 本机没有 `dotnet` 且 VM 未启动仍未执行。
- macOS 图形会话：`screencapture` 显示宿主机仍在锁屏界面；`ClipPlusMac` 进程存在，但菜单栏图标和设置面板无法做最终视觉确认。
- Computer Use：`list_apps` 能看到 Parallels Desktop、Windows 11 Dock Helper 和 `/private/tmp/ClipPlusMac.app` 正在运行；`get_app_state` 在锁屏下无法取得 Parallels 窗口，返回 `cgWindowNotFound`，ClipPlus 状态读取超时。
- Parallels Windows：`prlctl list --all --info` 显示 `Windows 11` 仍为 `stopped`，`EFI Secure boot: on`，`Shared clipboard mode: on`，IP 为空。
- Parallels 日志：`/Users/cc/Library/Logs/parallels.log` 记录 VM 启动后从 `VMS_RUNNING` 立刻进入 `VMS_STOPPING`/`VMS_STOPPED`，并出现 `PRL_ERR_SECURE_BOOT_VIOLATION`，中文提示为“安全启动功能防止操作系统启动”。调整 Parallels 安全启动或共享剪贴板属于系统/VM 设置变更，继续操作前需要用户明确确认。
- 后续确认后命令：关闭安全启动为 `prlctl set "Windows 11" --efi-secure-boot off`；关闭 Parallels 自带剪贴板共享为 `prlctl set "Windows 11" --shared-clipboard off`。

**2026-06-10 Windows VM 运行复验：**

- Parallels Windows：用户关闭 EFI Secure Boot 后，`Windows 11` VM 可正常启动；`prlctl list --all --info` 显示 `State: running`、`EFI Secure boot: off`、IP 为 `10.211.55.3`。
- Parallels 剪贴板：复验发现 `Shared clipboard mode` 仍为 `on`，已按测试目标切换为 `off` 并复核通过，避免污染 ClipPlus 剪贴板同步测试。
- Windows SDK：VM 内原本没有 `dotnet`；已安装官方 .NET SDK 8.0.422 到 `C:\dotnet`，用于运行 Windows WPF/xUnit 验证。
- Windows 测试：`cd C:\Mac\Home\proj\ClipPlus\apps\windows && C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过，2/2。
- Windows App：使用当前桌面用户会话启动 WPF App，设置窗口可见；系统托盘展开区可见 ClipPlus 托盘图标。
- macOS App：`ClipPlusMac` 进程存在，Accessibility 能识别菜单栏项 `粘贴`；宿主机在部分截图时回到锁屏界面，因此菜单栏弹出面板仍需一次解锁后的视觉截图补证。

**2026-06-10 双向文本同步复验：**

- 网络前置：Parallels 自带剪贴板共享保持 `off`；Windows VM IP 为 `10.211.55.3`，macOS Parallels 网卡 IP 为 `10.211.55.2`。
- 运行方式：macOS 和 Windows 端使用同一测试 Key `clipplus-test-key` 派生共享组；端到端测试启用 `CLIPPLUS_AUTO_TRUST=1` 和 `CLIPPLUS_PEER_HOSTS`，避免手动 UI 操作和虚拟网络广播不稳定影响测试。
- 设备发现：macOS 日志出现 Windows `peer hello`；Windows 日志出现 macOS `peer hello`，确认 UDP 发现双向可达。Windows 端发送改为复用监听端口 `47631`，避免 Windows 防火墙拦截无关联入站 UDP。
- Mac -> Windows 文本同步：macOS 写入系统剪贴板 `clipplus-mac-to-windows-20260610-095050`，4 秒后 VM 内 `Get-Clipboard -Raw` 返回同一字符串。
- Windows -> Mac 文本同步：Windows VM 写入系统剪贴板 `clipplus-windows-to-mac-20260610-095058`，4 秒后 macOS `pbpaste` 返回同一字符串。
- 日志检查：macOS 和 Windows 日志均记录 `published text clipboard`、`received text clipboard` 和 `peer hello`；用 `rg`/`Select-String` 检查日志未发现 `clipplus-test-key` 明文。
- 架构偏差：本次为打通可运行闭环，文本同步运行时暂时落在 macOS/Windows 原生壳内；后续仍需迁入 Rust core/FFI，避免长期维护两套协议实现。

**2026-06-10 图片同步 MVP 复验：**

- 实现范围：macOS 和 Windows 原生壳均支持 `image` 消息，使用 inline PNG + base64 + SHA-256 hash；原始 PNG 上限为 `32 KiB`，超过上限不发送，避免当前 UDP 单包模型在虚拟网络下过度分片。
- Mac -> Windows 图片同步：macOS 系统剪贴板写入 `target/test-assets/clipplus-one.png`，Windows VM 通过 WPF Clipboard 读取到 `WINDOWS_IMAGE=1x1`。
- Windows -> Mac 图片同步：Windows VM 写入 `target/test-assets/clipplus-two.png`，macOS 通过 `NSPasteboard` 读取到 `MAC_IMAGE=4x2`。该 PNG 由 AppKit 生成，因 backing scale 实际像素为 4x2。
- 日志检查：macOS 日志记录 `published image clipboard` 和 `received image clipboard`；Windows 日志记录 `received image clipboard` 和 `published image clipboard`。
- 限制：图片 MVP 仍走原生壳内 UDP 单包同步，未实现分片、重传或 TCP 图片正文传输。

**2026-06-10 开机启动与诊断导出复验：**

- 测试基础：Windows VM 已安装 OpenSSH Server，macOS 默认 SSH key 可直接登录 `ssh Administrator@10.211.55.3`；后续 Windows 测试优先通过 SSH 执行，避免依赖 Parallels UI。
- 开机启动：macOS 端接入 `SMAppService.mainApp`；Windows 端接入 HKCU `Software\Microsoft\Windows\CurrentVersion\Run`。单元测试使用可替换服务/注册表存储验证启用、禁用和状态读取逻辑。
- 诊断导出：macOS 和 Windows 设置页按钮已能导出 `status.json` 与脱敏后的 `clipplus.log` 到 Downloads 下的 `ClipPlus-Diagnostics-*` 目录。测试覆盖状态字段输出和 `clipplus-test-key`、剪贴板敏感文本脱敏。
- 验证：`./scripts/dev/check.sh` 通过；Windows VM 内通过 SSH 执行 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过 12/12。

**2026-06-10 手动设备确认复验：**

- 实现范围：macOS 与 Windows 原生壳新增 `trust` 消息；未确认设备只进入待确认列表，剪贴板文本/图片发布需要 `sharedKeyConfigured && sharingEnabled && trustedPeerCount > 0`。批准设备后，批准方发送面向该设备的 `trust` 消息；被批准方收到后反向信任批准方。
- UI：macOS 菜单栏 ClipPlus 面板在发现 Windows 后显示 `允许全部待确认设备（1）`；通过 Accessibility 点击该按钮完成一次真实 UI 手动确认。macOS 设置页和 Windows 设置窗口都已展示待确认设备列表，并支持逐个允许和全部允许。
- 负向测试：不设置 `CLIPPLUS_AUTO_TRUST`，两端只记录 `peer hello` 时，Mac 写入 `manual-before-approval-mac` 后，Windows 剪贴板仍保持基线值 `windows-baseline`，证明未确认前不发布剪贴板内容。
- 确认测试：点击 macOS 菜单栏 `允许全部待确认设备（1）` 后，Windows 日志出现 `peer trust accepted`，随后收到 Mac 端文本；Mac 日志后续也记录来自 Windows 的 `peer trust accepted`。重复 trust 已做幂等处理，避免周期性刷新状态和刷日志。
- 确认后双向文本同步：Mac 写入 `manual-after-approval-mac-1781059556` 后，Windows `Get-Clipboard -Raw` 返回同一字符串；Windows 写入 `manual-after-approval-windows-1781059570` 后，macOS `pbpaste` 返回同一字符串。
- 测试：macOS `swift test` 通过 17/17；Windows VM 内通过 SSH 执行 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过 16/16。

**2026-06-10 诊断 zip 导出复验：**

- macOS：`DiagnosticsExporter.export` 从导出目录改为直接生成 `ClipPlus-Diagnostics-*.zip`；zip 内包含 `status.json` 和 `clipplus.log`，测试使用 `/usr/bin/unzip` 解包验证字段和脱敏。
- Windows：`DiagnosticsExporter.Export` 从导出目录改为直接生成 `ClipPlus-Diagnostics-*.zip`；zip 内包含 `status.json` 和 `clipplus.log`，测试使用 `System.IO.Compression.ZipFile` 读取条目并验证脱敏。
- 脱敏：两端测试继续验证 `clipplus-test-key` 和剪贴板敏感文本不会出现在 status/log 条目里。
- 测试：macOS `swift test` 通过 17/17；Windows VM 内通过 SSH 执行 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过 16/16。
- 仍未完成项：开机启动真实系统写入开关的人工验证、文本/图片同步运行时迁入 Rust core/FFI；文件按需传输仍需继续补流式传输、hash 校验、原生延迟粘贴和 core/FFI 迁移。

**2026-06-10 文件按需传输 MVP 复验：**

- 实现范围：macOS 与 Windows 原生壳新增 `fileOffer` 消息、远端文件 offer UI、TCP `47632` 归档服务和接收端 `Downloads/ClipPlus-Received-<transferId>.zip` 降级接收路径。当前不是 Finder/Explorer 原生延迟粘贴，接收结果是 zip 包。
- 剪贴板读取：macOS 使用 `NSPasteboard` 读取 file URL；Windows 使用 WPF `Clipboard.GetFileDropList()` 读取 FileDropList。
- 传输模型：发送端只在 UDP offer 中广播相对文件名、文件数、总字节数、transferId 和归档端口，不广播本地绝对路径；接收端点击接收后再通过 TCP 请求归档正文。
- 单元测试：macOS 覆盖 file offer JSON 往返、远端文件 offer 接收回调、文件/目录 zip 写入；Windows 覆盖同等场景。
- 端到端复验方向：Windows -> macOS。Windows 侧用 `Set-Clipboard -Path` 设置真实 FileDropList；Windows 日志出现 `published file offer file_count=1`，macOS 日志出现 `received file offer file_count=1 byte_count=12`。
- 真实 UI 接收：通过 macOS 菜单栏 ClipPlus 面板点击远端文件接收按钮；macOS `Downloads` 生成 `ClipPlus-Received-ba332f94-3db9-427b-9e3c-ddcafb0e3e69.zip`。
- 内容校验：解压 zip 后包含 `windows-source.txt`；其内容 `1781061387` 与 Windows 源文件 `C:\Users\Administrator\AppData\Local\Temp\ClipPlusE2E\windows-source.txt` 读回内容一致。
- 日志证据：Windows 日志出现 `served file transfer file_count=1 byte_count=148`；macOS 日志出现 `downloaded file transfer byte_count=148`。随后日志文案已统一调整为 `served file archive` 和 `downloaded file archive`。
- 限制：归档当前一次性读入内存，并设置 512 MiB 上限；尚未做流式传输、hash 校验、断点续传、冲突文件选择、接收目录选择、原生延迟粘贴或 Rust core/FFI 统一实现。
- 最终验证：`cd apps/mac && swift test` 通过 20/20；Windows VM 内 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过 20/20；`./scripts/dev/check.sh` 通过；`git diff --check` 通过；macOS 和 Windows 日志未发现 `clipplus-test-key` 明文。
- 剩余项更新：文件按需传输已有 MVP 可运行闭环；仍需完成开机启动真实系统写入开关的人工验证，以及文本/图片/文件运行时迁入 Rust core/FFI。

**2026-06-10 Windows 开机启动真实读回复验：**

- 实现范围：Windows 测试新增 `StartupManagerWritesAndDeletesRealRunEntryWhenExplicitlyEnabled`，默认不写系统；只有设置 `CLIPPLUS_ENABLE_SYSTEM_STARTUP_TEST=1` 时才写入 HKCU Run，并在 `finally` 中恢复原有 `ClipPlus` 值。
- 路径选择：真实启动项使用 `ClipPlus.Windows.exe`，避免开发期 `dotnet ClipPlus.Windows.dll` 启动时 `Environment.ProcessPath` 只指向 `dotnet.exe`。
- 复验命令：Windows VM 内运行 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo --filter StartupManagerWritesAndDeletesRealRunEntryWhenExplicitlyEnabled`，并传入 `CLIPPLUS_ENABLE_SYSTEM_STARTUP_TEST=1` 与 `CLIPPLUS_SYSTEM_STARTUP_EXE=C:/Mac/Home/proj/ClipPlus/apps/windows/ClipPlus.Windows/bin/Debug/net8.0-windows/ClipPlus.Windows.exe`。
- 验证结果：该真实注册表测试通过 1/1；随后显式读取 `HKCU:\Software\Microsoft\Windows\CurrentVersion\Run` 下 `ClipPlus` 值，结果为 `ClipPlus Run entry absent`，确认测试未遗留开机启动项。
- 复验后续：该步骤先补齐 Windows 开机启动真实系统写入/读回/清理验证；macOS Login Item 真实读回复验见下一节。文本/图片/文件运行时仍需迁入 Rust core/FFI。

**2026-06-10 macOS Login Item 真实读回复验：**

- 实现范围：macOS App 新增调试 smoke test 入口 `CLIPPLUS_LOGIN_ITEM_SMOKE_TEST=1`，仅在显式设置环境变量时执行；流程为记录原始状态、`SMAppService.mainApp.register()`、读回 `LoginItemManager.isEnabled()`、`unregister()`、再次读回，最后恢复原始状态并退出。
- 单元测试：新增 `LoginItemSmokeTest.perform` 的 fake service 测试，覆盖原始关闭和原始开启两种状态，确认会恢复原始状态。
- 真实复验：当前源码 `swift build` 后替换 `/private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac`，运行 `CLIPPLUS_LOGIN_ITEM_SMOKE_TEST=1 /private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac`，输出 `login_item_smoke_test enabled_after_register=true disabled_after_unregister=true restored_original=true`，证明临时 app bundle 形态下 SMAppService 注册/注销均可系统读回且未遗留状态。
- 剩余项更新：macOS 和 Windows 开机启动均已有真实系统写入/读回/清理验证；文本/图片/文件运行时仍需迁入 Rust core/FFI，native library 打包随 app 发布仍需补齐。

**2026-06-10 Rust FFI 共享 Key 派生入口复验：**

- 实现范围：`clipplus-ffi` 新增 `clipplus_derive_group_id(raw_key)`，使用 `clipplus-crypto::SharedKeyMaterial::derive` 统一 Argon2 + BLAKE3 派生逻辑；null、空 Key、非 UTF-8 或派生失败返回 null，成功时返回需由 `clipplus_free_string` 释放的 C string。
- 验证：`cargo test -p clipplus-ffi` 通过 8/8，覆盖直接导出、lib re-export、空/null 输入拒绝，以及 `friend-lan-key` 派生为 `6OPi4Ya2nYZkISrKO0RGzQ`。
- 意义：这一步把 Rust core 的共享 Key 派生能力暴露到 FFI，后续 Swift/C# 应切到该入口，替换当前原生壳内 SHA-256 派生，消除长期协议分叉。
- 限制：Swift/C# 尚未链接并调用该 FFI；UDP 文本/图片/文件运行时仍在原生壳中，尚未迁入 Rust core/transport。

**2026-06-10 原生壳共享 Key 派生桥接复验：**

- macOS：`CoreBridge` 新增运行时加载 `clipplus_ffi` 的桥接逻辑，支持 `CLIPPLUS_FFI_LIBRARY_PATH` 或随 app 可执行文件/Frameworks 放置的 `libclipplus_ffi.dylib`；`SharedKeyHasher` 在 FFI 可用时使用 Rust 派生结果，否则保留旧 SHA-256 回退，避免未打包 FFI 库时 app 无法启动。
- macOS 验证：`CLIPPLUS_FFI_LIBRARY_PATH=/Users/cc/proj/ClipPlus/target/debug/libclipplus_ffi.dylib swift test` 通过 21/21；测试确认 `clipplus-test-key` 通过 FFI 派生为 `21YR2N3_wcdRPmEMLiuLMA`。普通 `swift test` 也通过 21/21。
- Windows：`CoreBridge` 新增 `NativeLibrary.TryLoad` 动态加载 `clipplus_ffi.dll` 的桥接逻辑，支持 `CLIPPLUS_FFI_LIBRARY_PATH` 或 app 输出目录下 `clipplus_ffi.dll`；`SharedKeyHasher` 在 DLL 可用时使用 Rust 派生结果，否则保留旧 SHA-256 回退。
- Windows 验证：Windows VM 内 `C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo` 通过 21/21，证明动态加载接口和回退路径不破坏 WPF app/test 构建。
- Windows FFI DLL 补齐：Windows VM 内 Rust host 和 .NET Host 均为 ARM64；初始 Build Tools 缺少 ARM64 VC Tools，`vcvarsall arm64` 后找不到 `link.exe`。已通过 Visual Studio Installer `modify --installPath "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools" --add Microsoft.VisualStudio.Component.VC.Tools.ARM64 --add Microsoft.VisualStudio.Component.Windows11SDK.26100 --quiet --norestart` 补装 ARM64 C++ 工具，`vswhere -requires Microsoft.VisualStudio.Component.VC.Tools.ARM64` 可读回实例，`vcvarsall arm64 && where link` 可找到 `HostARM64\arm64\link.exe`。
- Windows FFI 真实调用：Windows VM 内使用 `set "CARGO_TARGET_DIR=%TEMP%\ClipPlusRustTarget"` 避免 Parallels 共享目录文件系统异常，随后 `cargo build -p clipplus-ffi` 成功生成 `%TEMP%\ClipPlusRustTarget\debug\clipplus_ffi.dll`。设置 `CLIPPLUS_FFI_LIBRARY_PATH` 指向该 DLL 后，`C:\dotnet\dotnet.exe test ClipPlus.Windows.sln --nologo --filter CoreBridgeDerivesGroupIdWhenFfiLibraryIsAvailable` 通过 1/1，测试已收紧为显式设置 FFI 路径时加载失败必须失败，确认 Windows C# CoreBridge 真实调用 Rust FFI 并得到 `21YR2N3_wcdRPmEMLiuLMA`。
- 风险控制：默认不再自动搜索仓库 `target/debug`；开发/端到端启用 Rust FFI 必须显式传 `CLIPPLUS_FFI_LIBRARY_PATH` 或把 native library 放在 app 旁边，避免 macOS 自动用 Rust 派生而 Windows 默默回退导致组 ID 分叉。
- 剩余项更新：共享 Key 派生已有 Rust FFI 入口、macOS 真实调用证明和 Windows 真实 DLL/PInvoke 调用证明；Swift/C# 完全移除回退、native library 打包随 app 发布、以及 UDP 文本/图片/文件运行时迁入 Rust core/transport 仍未完成。

**2026-06-10 FFI 路径端到端文本同步复验：**

- 环境：Parallels `Windows 11` 运行中，`EFI Secure boot: off`，`Shared clipboard mode: off`，Windows IP `10.211.55.3`，macOS Parallels IP `10.211.55.2`。
- 启动方式：macOS 端使用当前源码重新 `swift build` 后替换 `/private/tmp/ClipPlusMac.app/Contents/MacOS/ClipPlusMac`，并设置 `CLIPPLUS_FFI_LIBRARY_PATH=/Users/cc/proj/ClipPlus/target/debug/libclipplus_ffi.dylib`。Windows 端使用 `C:\dotnet\dotnet.exe ClipPlus.Windows.dll` 启动，并设置 `CLIPPLUS_FFI_LIBRARY_PATH=%TEMP%\ClipPlusRustTarget\debug\clipplus_ffi.dll`。直接启动 `ClipPlus.Windows.exe` 会因 VM 未注册全局 .NET runtime 报 `hostfxr.dll not found`，测试手册已记录该故障定位。
- 发现和信任：两端使用 `CLIPPLUS_SHARED_KEY=clipplus-test-key`、`CLIPPLUS_AUTO_TRUST=1` 和显式 `CLIPPLUS_PEER_HOSTS`；macOS 与 Windows 日志均出现 `peer hello`，Windows 日志出现 `peer trust accepted`。
- Mac -> Windows：macOS 写入 `ffi-mac-to-windows-1781073898`，Windows `Get-Clipboard -Raw` 返回同一字符串；Windows 日志出现 `received text clipboard byte_count=29`。
- Windows -> Mac：Windows 写入 `ffi-windows-to-mac-1781073920`，macOS `pbpaste` 返回同一字符串；macOS 日志出现 `received text clipboard byte_count=29`。
- 日志检查：macOS `~/Library/Logs/ClipPlus/clipplus.log` 和 Windows `%LOCALAPPDATA%\ClipPlus\logs\clipplus.log` 均有文本发布/接收记录；匹配检查未出现 `clipplus-test-key` 明文。

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
