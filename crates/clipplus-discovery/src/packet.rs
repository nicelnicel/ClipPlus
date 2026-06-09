use serde::{Deserialize, Deserializer, Serialize, Serializer};
use thiserror::Error;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum PeerCapability {
    Text,
    Image,
    File,
    Unknown(String),
}

impl PeerCapability {
    fn as_wire_value(&self) -> &str {
        match self {
            Self::Text => "text",
            Self::Image => "image",
            Self::File => "file",
            Self::Unknown(value) => value,
        }
    }
}

impl Serialize for PeerCapability {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(self.as_wire_value())
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
    #[error("discovery packet JSON error: {0}")]
    Json(#[from] serde_json::Error),
    #[error("invalid discovery packet field: {0}")]
    InvalidField(&'static str),
}

impl DiscoveryPacket {
    pub fn new_for_test(group_id: impl Into<String>, device_id: impl Into<String>) -> Self {
        Self {
            group_id: group_id.into(),
            device_id: device_id.into(),
            device_name: "ClipPlus Test Device".to_string(),
            platform: "test-platform".to_string(),
            public_key: "test-public-key".to_string(),
            app_version: "0.0.0-test".to_string(),
            capabilities: vec![
                PeerCapability::Text,
                PeerCapability::Image,
                PeerCapability::File,
            ],
        }
    }

    pub fn matches_group(&self, group_id: &str) -> bool {
        !self.group_id.trim().is_empty() && !group_id.trim().is_empty() && self.group_id == group_id
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
