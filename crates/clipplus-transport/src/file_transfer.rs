use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Available,
    Active,
    Completed,
    Failed,
    Expired,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum FileTransferError {
    #[error("invalid file transfer field: {0}")]
    InvalidField(&'static str),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferRequest {
    pub transfer_id: String,
    pub expires_after_minutes: u64,
    pub state: TransferState,
}

impl FileTransferRequest {
    pub fn new(
        transfer_id: impl Into<String>,
        expires_after_minutes: u64,
    ) -> Result<Self, FileTransferError> {
        let transfer_id = transfer_id.into();
        let transfer_id = transfer_id.trim();
        if transfer_id.is_empty() {
            return Err(FileTransferError::InvalidField("transfer_id"));
        }

        Ok(Self {
            transfer_id: transfer_id.to_string(),
            expires_after_minutes,
            state: TransferState::Available,
        })
    }

    pub fn new_for_test(transfer_id: impl Into<String>, expires_after_minutes: u64) -> Self {
        Self::new(transfer_id, expires_after_minutes).expect("valid file transfer id")
    }

    pub fn is_expired_at_minute(&self, elapsed_minutes: u64) -> bool {
        elapsed_minutes > self.expires_after_minutes
    }
}
