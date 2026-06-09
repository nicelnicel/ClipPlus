#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Available,
    Active,
    Completed,
    Failed,
    Expired,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferRequest {
    pub transfer_id: String,
    pub expires_after_minutes: u32,
    pub state: TransferState,
}

impl FileTransferRequest {
    pub fn new_for_test(transfer_id: impl Into<String>, expires_after_minutes: u32) -> Self {
        Self {
            transfer_id: transfer_id.into(),
            expires_after_minutes,
            state: TransferState::Available,
        }
    }

    pub fn is_expired_at_minute(&self, elapsed_minutes: u32) -> bool {
        elapsed_minutes > self.expires_after_minutes
    }
}
