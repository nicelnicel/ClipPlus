use std::io::{Cursor, Write};

use thiserror::Error;
use zip::{write::SimpleFileOptions, ZipWriter};

use crate::{redaction::RedactedConfig, status::RuntimeStatus};

#[derive(Debug, Error)]
pub enum ExportError {
    #[error("failed to serialize diagnostics JSON: {0}")]
    Json(#[from] serde_json::Error),
    #[error("failed to write diagnostics zip: {0}")]
    Zip(#[from] zip::result::ZipError),
    #[error("failed to write diagnostics data: {0}")]
    Io(#[from] std::io::Error),
}

pub fn export_diagnostics_zip(
    status: &RuntimeStatus,
    config: &RedactedConfig,
    log_text: &str,
) -> Result<Vec<u8>, ExportError> {
    let mut writer = ZipWriter::new(Cursor::new(Vec::new()));
    let options = SimpleFileOptions::default();

    writer.start_file("runtime-status.json", options)?;
    writer.write_all(&serde_json::to_vec_pretty(status)?)?;

    writer.start_file("config-redacted.json", options)?;
    writer.write_all(&serde_json::to_vec_pretty(config)?)?;

    writer.start_file("logs/clipplus.log", options)?;
    writer.write_all(redact_log_text(log_text).as_bytes())?;

    let cursor = writer.finish()?;
    Ok(cursor.into_inner())
}

fn redact_log_text(log_text: &str) -> String {
    log_text
        .lines()
        .map(redact_log_line)
        .collect::<Vec<_>>()
        .join("\n")
        + if log_text.ends_with('\n') { "\n" } else { "" }
}

fn redact_log_line(line: &str) -> String {
    ["shared_key", "key", "token"]
        .into_iter()
        .fold(line.to_string(), |current, name| {
            redact_key_value(&current, name)
        })
}

fn redact_key_value(line: &str, name: &str) -> String {
    let pattern = format!("{name}=");
    let mut redacted = String::with_capacity(line.len());
    let mut rest = line;

    while let Some(index) = rest.find(&pattern) {
        let (prefix, matched) = rest.split_at(index);
        redacted.push_str(prefix);
        redacted.push_str(&pattern);
        redacted.push_str("<redacted>");

        let value_start = pattern.len();
        let value_end = matched[value_start..]
            .find(|ch: char| ch.is_whitespace() || ch == ',' || ch == ';')
            .map(|end| value_start + end)
            .unwrap_or(matched.len());
        rest = &matched[value_end..];
    }

    redacted.push_str(rest);
    redacted
}
