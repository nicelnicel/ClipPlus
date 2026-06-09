use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum PeerCapability {
    Text,
    Image,
    File,
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
        self.group_id == group_id
    }

    pub fn to_json(&self) -> Result<String, DiscoveryPacketError> {
        Ok(serde_json::to_string(self)?)
    }

    pub fn from_json(value: &str) -> Result<Self, DiscoveryPacketError> {
        Ok(serde_json::from_str(value)?)
    }
}
