use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{SigningKey, VerifyingKey};
use rand_core::OsRng;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeviceIdentity {
    pub device_id: String,
    pub device_name: String,
    pub platform: String,
    pub public_key: String,
    pub private_key: String,
}

impl DeviceIdentity {
    pub fn generate(device_name: impl Into<String>, platform: impl Into<String>) -> Self {
        let signing_key = SigningKey::generate(&mut OsRng);
        let verifying_key: VerifyingKey = signing_key.verifying_key();

        Self {
            device_id: Uuid::new_v4().to_string(),
            device_name: device_name.into(),
            platform: platform.into(),
            public_key: URL_SAFE_NO_PAD.encode(verifying_key.to_bytes()),
            private_key: URL_SAFE_NO_PAD.encode(signing_key.to_bytes()),
        }
    }

    pub fn fingerprint_short(&self) -> String {
        let hash = blake3::hash(self.public_key.as_bytes())
            .to_hex()
            .to_string();
        format!(
            "{}-{}",
            &hash[0..4].to_uppercase(),
            &hash[4..8].to_uppercase()
        )
    }
}
