use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandshakeState {
    PendingApproval,
    Trusted,
    Rejected,
    KeyMismatch,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SessionError {
    #[error("invalid peer session field: {0}")]
    InvalidField(&'static str),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerSession {
    pub device_id: String,
    pub state: HandshakeState,
}

impl PeerSession {
    pub fn new(device_id: impl Into<String>, state: HandshakeState) -> Self {
        Self::try_new(device_id, state).expect("valid peer session device id")
    }

    pub fn try_new(
        device_id: impl Into<String>,
        state: HandshakeState,
    ) -> Result<Self, SessionError> {
        let device_id = device_id.into();
        let device_id = device_id.trim();
        if device_id.is_empty() {
            return Err(SessionError::InvalidField("device_id"));
        }

        Ok(Self {
            device_id: device_id.to_string(),
            state,
        })
    }

    pub fn can_sync(&self) -> bool {
        self.state == HandshakeState::Trusted && !self.device_id.trim().is_empty()
    }
}
