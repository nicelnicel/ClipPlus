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
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, TransportMessageError> {
        let message = serde_json::from_str::<Self>(value)?;
        message.validate()?;
        Ok(message)
    }

    fn validate(&self) -> Result<(), TransportMessageError> {
        if self.sender_device_id.trim().is_empty() {
            return Err(Self::invalid_field("sender_device_id"));
        }

        if serde_json::from_str::<serde_json::Value>(&self.payload_json).is_err() {
            return Err(Self::invalid_field("payload_json"));
        }

        Ok(())
    }

    fn invalid_field(field: &'static str) -> TransportMessageError {
        use serde::de::Error as _;

        TransportMessageError::Json(serde_json::Error::custom(format!(
            "invalid transport message field: {field}"
        )))
    }
}
