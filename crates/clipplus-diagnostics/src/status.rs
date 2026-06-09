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
            last_clipboard_event_summary: Some("text bytes=32".to_string()),
            last_error: None,
            startup_enabled: false,
            log_level: "info".to_string(),
        }
    }
}
