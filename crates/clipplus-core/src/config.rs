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
            ClipboardPayload::Image { byte_size, .. } => {
                self.image && *byte_size <= self.image_limit.bytes()
            }
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
