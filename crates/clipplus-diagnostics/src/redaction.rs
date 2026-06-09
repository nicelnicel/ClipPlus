use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RedactedConfig {
    pub shared_key_configured: bool,
    pub group_id_prefix: String,
    pub device_id_prefix: String,
    pub trusted_peer_count: usize,
    pub paused_peer_count: usize,
}

pub fn redact_config(
    shared_key_configured: bool,
    _raw_key: &str,
    group_id: &str,
    device_id: &str,
    trusted_peer_count: usize,
    paused_peer_count: usize,
) -> RedactedConfig {
    RedactedConfig {
        shared_key_configured,
        group_id_prefix: prefix(group_id),
        device_id_prefix: prefix(device_id),
        trusted_peer_count,
        paused_peer_count,
    }
}

fn prefix(value: &str) -> String {
    value.chars().take(8).collect()
}
