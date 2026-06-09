use std::str::FromStr;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum DeviceIdError {
    #[error("device id cannot be empty")]
    Empty,
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct DeviceId(String);

impl DeviceId {
    pub fn new(value: impl Into<String>) -> Result<Self, DeviceIdError> {
        let value = value.into();
        let trimmed = value.trim();

        if trimmed.is_empty() {
            return Err(DeviceIdError::Empty);
        }

        Ok(Self(trimmed.to_string()))
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl FromStr for DeviceId {
    type Err = DeviceIdError;

    fn from_str(value: &str) -> Result<Self, Self::Err> {
        Self::new(value)
    }
}

impl TryFrom<String> for DeviceId {
    type Error = DeviceIdError;

    fn try_from(value: String) -> Result<Self, Self::Error> {
        Self::new(value)
    }
}

impl From<DeviceId> for String {
    fn from(value: DeviceId) -> Self {
        value.0
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
