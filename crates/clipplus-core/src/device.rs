use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DeviceId(String);

impl DeviceId {
    pub fn from_static(value: &'static str) -> Self {
        Self(value.to_string())
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum Platform {
    MacOS,
    Windows,
    Ios,
    Android,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum DeviceState {
    Pending,
    Trusted,
    Paused,
    Rejected,
    Offline,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PeerDevice {
    pub id: DeviceId,
    pub name: String,
    pub platform: Platform,
    pub state: DeviceState,
}

impl PeerDevice {
    pub fn new(
        id: DeviceId,
        name: impl Into<String>,
        platform: Platform,
        state: DeviceState,
    ) -> Self {
        Self {
            id,
            name: name.into(),
            platform,
            state,
        }
    }

    pub fn can_sync(&self) -> bool {
        matches!(self.state, DeviceState::Trusted)
    }
}
