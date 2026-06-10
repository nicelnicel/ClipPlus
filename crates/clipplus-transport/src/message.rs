use serde::{Deserialize, Serialize};
use thiserror::Error;
use uuid::Uuid;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum NativeClipboardMessageKind {
    Hello,
    Trust,
    Text,
    Image,
    FileOffer,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeClipboardMessage {
    pub kind: NativeClipboardMessageKind,
    pub protocol_version: u8,
    pub group_id: String,
    pub sender_device_id: String,
    pub sender_device_name: String,
    pub event_id: Uuid,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_base64: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_byte_size: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub image_content_hash: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub approved_device_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub transfer_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub files: Option<Vec<NativeFileTransferItem>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub archive_port: Option<u16>,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct NativeFileTransferItem {
    pub relative_path: String,
    pub byte_size: u64,
    pub is_directory: bool,
}

#[derive(Debug, Error)]
pub enum NativeClipboardMessageError {
    #[error("native clipboard message JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("invalid native clipboard message field: {0}")]
    InvalidField(&'static str),
}

impl NativeClipboardMessage {
    pub fn text(
        group_id: impl Into<String>,
        sender_device_id: impl Into<String>,
        sender_device_name: impl Into<String>,
        text: impl Into<String>,
    ) -> Result<Self, NativeClipboardMessageError> {
        let message = Self {
            kind: NativeClipboardMessageKind::Text,
            protocol_version: 1,
            group_id: group_id.into(),
            sender_device_id: sender_device_id.into(),
            sender_device_name: sender_device_name.into(),
            event_id: Uuid::new_v4(),
            text: Some(text.into()),
            image_base64: None,
            image_byte_size: None,
            image_content_hash: None,
            approved_device_id: None,
            transfer_id: None,
            files: None,
            archive_port: None,
            created_at: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Millis, true),
        };
        message.validate()?;
        Ok(message)
    }

    pub fn to_json(&self) -> Result<String, NativeClipboardMessageError> {
        self.validate()?;
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, NativeClipboardMessageError> {
        let message = serde_json::from_str::<Self>(value)?;
        message.validate()?;
        Ok(message)
    }

    fn validate(&self) -> Result<(), NativeClipboardMessageError> {
        if self.protocol_version != 1 {
            return Err(NativeClipboardMessageError::InvalidField(
                "protocol_version",
            ));
        }
        if self.group_id.trim().is_empty() {
            return Err(NativeClipboardMessageError::InvalidField("group_id"));
        }
        if self.sender_device_id.trim().is_empty() {
            return Err(NativeClipboardMessageError::InvalidField(
                "sender_device_id",
            ));
        }
        if self.sender_device_name.trim().is_empty() {
            return Err(NativeClipboardMessageError::InvalidField(
                "sender_device_name",
            ));
        }
        if matches!(self.kind, NativeClipboardMessageKind::Text)
            && self.text.as_deref().is_none_or(str::is_empty)
        {
            return Err(NativeClipboardMessageError::InvalidField("text"));
        }

        Ok(())
    }
}

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
    #[error("transport message JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("invalid transport message field: {0}")]
    InvalidField(&'static str),
}

impl TransportMessage {
    pub fn new_for_test(kind: TransportMessageKind) -> Self {
        Self {
            message_id: Uuid::new_v4(),
            kind,
            sender_device_id: "test-device".to_string(),
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
