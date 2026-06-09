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
