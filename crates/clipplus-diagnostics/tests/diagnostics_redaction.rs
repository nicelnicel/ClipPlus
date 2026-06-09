use std::collections::{BTreeMap, BTreeSet};
use std::io::Read;

use clipplus_diagnostics::export::export_diagnostics_zip;
use clipplus_diagnostics::redaction::{redact_config, redact_sensitive_text};
use clipplus_diagnostics::status::{
    ClipboardContentKind, ClipboardEventSummary, ContentTypeStatus, RuntimeStatus,
    SafeDiagnosticMessage,
};

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
fn redacted_config_uses_eight_character_prefixes_for_long_ids() {
    let redacted = redact_config(
        true,
        "raw-secret-key",
        "group-123456789",
        "device-secret-id",
        2,
        1,
    );

    assert_eq!(redacted.group_id_prefix, "group-12");
    assert_eq!(redacted.device_id_prefix, "device-s");
}

#[test]
fn runtime_status_serializes_without_clipboard_content_or_error_secrets() {
    let mut status = RuntimeStatus::new_for_test();
    status.last_error = Some(SafeDiagnosticMessage::new("failed token=runtime-secret"));
    let json = serde_json::to_string(&status).unwrap();

    assert!(json.contains("connected_peer_count"));
    assert!(json.contains("last_clipboard_event_summary"));
    assert!(json.contains("\"content_kind\":\"Text\""));
    assert!(json.contains("\"byte_count\":32"));
    assert!(!json.contains("password copied from clipboard"));
    assert!(!json.contains("runtime-secret"));
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
fn clipboard_event_summary_constructors_do_not_accept_raw_content() {
    assert_eq!(
        ClipboardEventSummary::text(32).content_kind,
        ClipboardContentKind::Text
    );
    assert_eq!(ClipboardEventSummary::text(32).byte_count, 32);
    assert_eq!(ClipboardEventSummary::image(4096).byte_count, 4096);
    assert_eq!(ClipboardEventSummary::file_list(3).item_count, Some(3));
}

#[test]
fn sensitive_text_redaction_handles_common_secret_formats() {
    let redacted = redact_sensitive_text(
        "\
KEY=upper-secret
Token=bearer-secret
shared_key: colon-secret
key = spaced-secret
\"token\":\"json-secret\"
\"shared_key\": \"json-shared-secret\"
?Token=query-secret&next=1
key='single-quoted-secret'
token=comma-secret,
shared_key=semi-secret;
",
    );

    for secret in [
        "upper-secret",
        "bearer-secret",
        "colon-secret",
        "spaced-secret",
        "json-secret",
        "json-shared-secret",
        "query-secret",
        "single-quoted-secret",
        "comma-secret",
        "semi-secret",
    ] {
        assert!(!redacted.contains(secret), "{secret} leaked in {redacted}");
    }
    assert!(redacted.contains("&next=1"));
}

#[test]
fn diagnostics_zip_contains_stable_redacted_entries() {
    let status = RuntimeStatus::new_for_test();
    let config = redact_config(
        true,
        "raw-secret-key",
        "group-123456789",
        "device-secret-id",
        2,
        1,
    );
    let log_text = "\
info: started
key=raw-secret-key
shared_key=another-secret
token=bearer-token-value
KEY=upper-secret
Token=bearer-secret
shared_key: colon-secret
key = spaced-secret
\"token\":\"json-secret\"
\"shared_key\": \"json-shared-secret\"
?Token=query-secret&next=1
key='single-quoted-secret'
token=comma-secret,
shared_key=semi-secret;
";

    let bytes = export_diagnostics_zip(&status, &config, log_text).unwrap();
    let entries = read_zip_entries(bytes);
    assert_eq!(
        entries.keys().cloned().collect::<BTreeSet<_>>(),
        BTreeSet::from([
            "config-redacted.json".to_string(),
            "logs/clipplus.log".to_string(),
            "runtime-status.json".to_string(),
        ])
    );

    let runtime_json: serde_json::Value =
        serde_json::from_str(entries.get("runtime-status.json").unwrap()).unwrap();
    let config_json: serde_json::Value =
        serde_json::from_str(entries.get("config-redacted.json").unwrap()).unwrap();
    let logs = entries.get("logs/clipplus.log").unwrap();

    let runtime_text = serde_json::to_string(&runtime_json).unwrap();
    let config_text = serde_json::to_string(&config_json).unwrap();

    assert!(logs.contains("info: started"));
    assert!(logs.contains("&next=1"));
    assert_eq!(config_json["group_id_prefix"], "group-12");
    assert_eq!(config_json["device_id_prefix"], "device-s");
    assert!(runtime_text.contains("connected_peer_count"));
    assert!(config_text.contains("group-12"));
    assert!(config_text.contains("device-s"));
    assert!(!config_text.contains("raw-secret-key"));
    assert!(!config_text.contains("group-123456789"));
    assert!(!config_text.contains("device-secret-id"));

    assert!(!logs.contains("raw-secret-key"));
    assert!(!logs.contains("another-secret"));
    assert!(!logs.contains("bearer-token-value"));
    assert!(!logs.contains("upper-secret"));
    assert!(!logs.contains("bearer-secret"));
    assert!(!logs.contains("colon-secret"));
    assert!(!logs.contains("spaced-secret"));
    assert!(!logs.contains("json-secret"));
    assert!(!logs.contains("json-shared-secret"));
    assert!(!logs.contains("query-secret"));
    assert!(!logs.contains("single-quoted-secret"));
    assert!(!logs.contains("comma-secret"));
    assert!(!logs.contains("semi-secret"));
}

fn read_zip_entries(bytes: Vec<u8>) -> BTreeMap<String, String> {
    let reader = std::io::Cursor::new(bytes);
    let mut archive = zip::ZipArchive::new(reader).unwrap();
    let mut entries = BTreeMap::new();

    for index in 0..archive.len() {
        let mut file = archive.by_index(index).unwrap();
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        entries.insert(file.name().to_string(), contents);
    }

    entries
}
