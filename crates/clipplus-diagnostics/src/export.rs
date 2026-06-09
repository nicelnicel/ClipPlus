use std::io::{Cursor, Write};

use thiserror::Error;
use zip::{write::SimpleFileOptions, ZipWriter};

use crate::{
    redaction::{redact_sensitive_text, RedactedConfig},
    status::RuntimeStatus,
};

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
    writer.write_all(redact_sensitive_text(log_text).as_bytes())?;

    let cursor = writer.finish()?;
    Ok(cursor.into_inner())
}
