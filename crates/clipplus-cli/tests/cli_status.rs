use std::process::Command;

use serde_json::Value;

#[test]
fn cli_status_outputs_runtime_status_json() {
    let output = Command::new(env!("CARGO_BIN_EXE_clipplus-cli"))
        .arg("status")
        .output()
        .expect("clipplus-cli status should run");

    assert!(
        output.status.success(),
        "status should succeed, stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    assert!(stdout.contains("core_version"));
    assert!(!stdout.contains("raw-secret-key"));
}

#[test]
fn cli_diagnose_outputs_not_started_components() {
    let output = Command::new(env!("CARGO_BIN_EXE_clipplus-cli"))
        .arg("diagnose")
        .output()
        .expect("clipplus-cli diagnose should run");

    assert!(
        output.status.success(),
        "diagnose should succeed, stderr: {}",
        String::from_utf8_lossy(&output.stderr)
    );

    let stdout = String::from_utf8_lossy(&output.stdout);
    let value: Value = serde_json::from_str(&stdout).expect("diagnose output should be json");

    assert_eq!(value["network"], "not_started");
    assert_eq!(value["clipboard"], "not_started");
    assert_eq!(value["file_transfer"], "not_started");
}

#[test]
fn cli_unknown_command_returns_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_clipplus-cli"))
        .arg("missing")
        .output()
        .expect("clipplus-cli missing should run");

    assert!(!output.status.success());

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("未知命令: missing"));
}

#[test]
fn cli_without_command_returns_usage_error() {
    let output = Command::new(env!("CARGO_BIN_EXE_clipplus-cli"))
        .output()
        .expect("clipplus-cli should run");

    assert!(!output.status.success());

    let stderr = String::from_utf8_lossy(&output.stderr);
    assert!(stderr.contains("用法: clipplus-cli status | diagnose"));
}
