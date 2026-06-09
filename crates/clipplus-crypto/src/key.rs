use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use std::fmt;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum KeyError {
    #[error("共享 Key 不能为空")]
    Empty,
    #[error("共享 Key 派生失败: {0}")]
    Kdf(String),
}

#[derive(Clone, PartialEq, Eq)]
pub struct SharedKeyMaterial {
    pub group_id: String,
    pub verifier: String,
}

impl fmt::Debug for SharedKeyMaterial {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter
            .debug_struct("SharedKeyMaterial")
            .field("group_id", &self.group_id)
            .field("verifier", &"<redacted>")
            .finish()
    }
}

impl SharedKeyMaterial {
    pub fn derive(raw_key: &str) -> Result<Self, KeyError> {
        let normalized = raw_key.trim();
        if normalized.is_empty() {
            return Err(KeyError::Empty);
        }

        let argon2 = argon2::Argon2::default();
        let mut stretched = [0u8; 32];
        argon2
            .hash_password_into(
                normalized.as_bytes(),
                b"clipplus.shared-key.v1",
                &mut stretched,
            )
            .map_err(|error| KeyError::Kdf(error.to_string()))?;

        let group_hash = blake3::derive_key("clipplus.group.v1", &stretched);
        let verifier_hash = blake3::derive_key("clipplus.verifier.v1", &stretched);

        Ok(Self {
            group_id: URL_SAFE_NO_PAD.encode(&group_hash[..16]),
            verifier: URL_SAFE_NO_PAD.encode(&verifier_hash[..16]),
        })
    }
}
