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
