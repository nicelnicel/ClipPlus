#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum HandshakeState {
    PendingApproval,
    Trusted,
    Rejected,
    KeyMismatch,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PeerSession {
    pub device_id: String,
    pub state: HandshakeState,
}

impl PeerSession {
    pub fn new(device_id: impl Into<String>, state: HandshakeState) -> Self {
        Self {
            device_id: device_id.into(),
            state,
        }
    }

    pub fn can_sync(&self) -> bool {
        self.state == HandshakeState::Trusted
    }
}
