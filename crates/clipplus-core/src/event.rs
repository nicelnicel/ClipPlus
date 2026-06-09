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
    pub fn text_for_test(text: &str) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            origin_device_id: DeviceId::from_static("test-device"),
            created_at: Utc::now(),
            payload: ClipboardPayload::Text {
                text: text.to_string(),
                byte_size: text.len(),
            },
        }
    }

    pub fn image_for_test(byte_size: usize) -> Self {
        Self {
            event_id: Uuid::new_v4(),
            origin_device_id: DeviceId::from_static("test-device"),
            created_at: Utc::now(),
            payload: ClipboardPayload::Image {
                format: ImageFormat::Png,
                byte_size,
                width: 100,
                height: 100,
                content_hash: format!("test-image-{byte_size}"),
            },
        }
    }
}
