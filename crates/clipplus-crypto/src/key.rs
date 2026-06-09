use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum KeyError {
    #[error("共享 Key 不能为空")]
    Empty,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SharedKeyMaterial {
    pub group_id: String,
    pub verifier: String,
}

impl SharedKeyMaterial {
    pub fn derive(raw_key: &str) -> Result<Self, KeyError> {
        let normalized = raw_key.trim();
        if normalized.is_empty() {
            return Err(KeyError::Empty);
        }

        let group_hash = blake3::derive_key("clipplus.group.v1", normalized.as_bytes());
        let verifier_hash = blake3::derive_key("clipplus.verifier.v1", normalized.as_bytes());

        Ok(Self {
            group_id: URL_SAFE_NO_PAD.encode(&group_hash[..16]),
            verifier: URL_SAFE_NO_PAD.encode(&verifier_hash[..16]),
        })
    }
}
