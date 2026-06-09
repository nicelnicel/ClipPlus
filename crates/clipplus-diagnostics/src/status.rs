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
    pub fn text(byte_count: usize) -> Self {
        Self {
            content_kind: ClipboardContentKind::Text,
            byte_count,
            item_count: None,
            source_device_id_prefix: None,
        }
    }

    pub fn image(byte_count: usize) -> Self {
        Self {
            content_kind: ClipboardContentKind::Image,
            byte_count,
            item_count: None,
            source_device_id_prefix: None,
        }
    }

    pub fn file_list(item_count: usize) -> Self {
        Self {
            content_kind: ClipboardContentKind::FileList,
            byte_count: 0,
            item_count: Some(item_count),
            source_device_id_prefix: None,
        }
    }
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
            app_version: "0.1.0-test".to_string(),
            core_version: "0.1.0-test".to_string(),
            platform: "test".to_string(),
            device_id_prefix: "device-t".to_string(),
            shared_key_configured: true,
            sharing_enabled: true,
            enabled_content_types: ContentTypeStatus {
                text: true,
                image: false,
                file: true,
            },
            discovery_status: "ready".to_string(),
            connected_peer_count: 1,
            pending_peer_count: 0,
            paused_peer_count: 0,
            last_clipboard_event_summary: Some(ClipboardEventSummary::text(32)),
            last_error: None,
            startup_enabled: false,
            log_level: "info".to_string(),
        }
    }
}
