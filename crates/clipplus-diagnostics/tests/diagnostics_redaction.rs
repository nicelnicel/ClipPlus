use std::io::Read;

use clipplus_diagnostics::export::export_diagnostics_zip;
use clipplus_diagnostics::redaction::{redact_config, RedactedConfig};
use clipplus_diagnostics::status::{ContentTypeStatus, RuntimeStatus};

#[test]
fn redacted_config_does_not_include_raw_key() {
    let redacted = redact_config(
        true,
        "raw-secret-key",
        "ab12cd34ef56",
        "device-secret-id",
        2,
        1,
    );

    assert!(redacted.shared_key_configured);
    assert_eq!(redacted.group_id_prefix, "ab12cd34");
    assert_eq!(redacted.device_id_prefix, "device-s");
    assert!(!serde_json::to_string(&redacted)
        .unwrap()
        .contains("raw-secret-key"));
}

#[test]
fn runtime_status_serializes_without_clipboard_content() {
    let status = RuntimeStatus::new_for_test();
    let json = serde_json::to_string(&status).unwrap();

    assert!(json.contains("connected_peer_count"));
    assert!(!json.contains("password copied from clipboard"));
}

#[test]
fn content_type_status_reports_enabled_types() {
    let status = ContentTypeStatus {
        text: true,
        image: false,
        file: true,
    };
    assert_eq!(status.enabled_names(), vec!["text", "file"]);
}

#[test]
fn diagnostics_zip_redacts_secret_values_from_logs() {
    let status = RuntimeStatus::new_for_test();
    let config = RedactedConfig {
        shared_key_configured: true,
        group_id_prefix: "group-12".to_string(),
        device_id_prefix: "device-3".to_string(),
        trusted_peer_count: 2,
        paused_peer_count: 1,
    };
    let log_text = "\
info: started
key=raw-secret-key
shared_key=another-secret
token=bearer-token-value
";

    let bytes = export_diagnostics_zip(&status, &config, log_text).unwrap();
    let reader = std::io::Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader).unwrap();
    let mut logs = String::new();
    archive
        .by_name("logs/clipplus.log")
        .unwrap()
        .read_to_string(&mut logs)
        .unwrap();

    assert!(logs.contains("info: started"));
    assert!(!logs.contains("raw-secret-key"));
    assert!(!logs.contains("another-secret"));
    assert!(!logs.contains("bearer-token-value"));
}
