use std::fs::File;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::path::{Path, PathBuf};
use std::time::Duration;

use thiserror::Error;
use zip::write::SimpleFileOptions;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransferState {
    Available,
    Active,
    Completed,
    Failed,
    Expired,
}

#[derive(Debug, Error)]
pub enum FileTransferError {
    #[error("invalid file transfer field: {0}")]
    InvalidField(&'static str),
    #[error("file transfer io error: {0}")]
    Io(#[from] std::io::Error),
    #[error("file transfer zip error: {0}")]
    Zip(#[from] zip::result::ZipError),
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

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferArchiveSummary {
    pub file_count: usize,
    pub byte_count: u64,
}

pub struct FileTransferArchive;

impl FileTransferArchive {
    pub fn write_zip(
        source_paths: &[PathBuf],
        archive_path: &Path,
    ) -> Result<FileTransferArchiveSummary, FileTransferError> {
        if source_paths.is_empty() {
            return Err(FileTransferError::InvalidField("source_paths"));
        }
        if archive_path.parent().is_none_or(|parent| !parent.exists()) {
            return Err(FileTransferError::InvalidField("archive_parent"));
        }

        if archive_path.exists() {
            std::fs::remove_file(archive_path)?;
        }

        let file = File::create(archive_path)?;
        let mut writer = zip::ZipWriter::new(file);
        let mut summary = FileTransferArchiveSummary {
            file_count: 0,
            byte_count: 0,
        };

        for source_path in source_paths {
            if source_path.is_file() {
                let entry_name = source_path
                    .file_name()
                    .and_then(|name| name.to_str())
                    .ok_or(FileTransferError::InvalidField("source_path"))?
                    .to_string();
                write_file_entry(&mut writer, source_path, &entry_name, &mut summary)?;
                continue;
            }

            if source_path.is_dir() {
                let base_path = source_path
                    .parent()
                    .ok_or(FileTransferError::InvalidField("source_path"))?;
                write_directory_entries(&mut writer, source_path, base_path, &mut summary)?;
            }
        }

        writer.finish()?;
        summary.byte_count = std::fs::metadata(archive_path)?.len();

        Ok(summary)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct FileTransferDownloadSummary {
    pub byte_count: u64,
}

pub struct FileTransferDownload;

impl FileTransferDownload {
    pub const MAX_ARCHIVE_BYTES: u64 = 512 * 1024 * 1024;

    pub fn download_to_path(
        host: &str,
        port: u16,
        transfer_id: &str,
        destination_path: &Path,
    ) -> Result<FileTransferDownloadSummary, FileTransferError> {
        let host = host.trim();
        let transfer_id = transfer_id.trim();
        if host.is_empty() {
            return Err(FileTransferError::InvalidField("host"));
        }
        if port == 0 {
            return Err(FileTransferError::InvalidField("port"));
        }
        if transfer_id.is_empty() {
            return Err(FileTransferError::InvalidField("transfer_id"));
        }
        if destination_path
            .parent()
            .is_none_or(|parent| !parent.exists())
        {
            return Err(FileTransferError::InvalidField("destination_parent"));
        }

        let target = (host, port)
            .to_socket_addrs()?
            .next()
            .ok_or(FileTransferError::InvalidField("host"))?;
        let mut stream = TcpStream::connect_timeout(&target, Duration::from_secs(5))?;
        stream.set_read_timeout(Some(Duration::from_secs(30)))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;
        stream.write_all(transfer_id.as_bytes())?;
        stream.write_all(b"\n")?;

        let mut length_bytes = [0_u8; 8];
        stream.read_exact(&mut length_bytes)?;
        let byte_count = u64::from_be_bytes(length_bytes);
        if byte_count > Self::MAX_ARCHIVE_BYTES {
            return Err(FileTransferError::InvalidField("archive_size"));
        }

        let mut file = File::create(destination_path)?;
        let mut remaining = byte_count;
        let mut buffer = [0_u8; 64 * 1024];
        while remaining > 0 {
            let read_len = remaining.min(buffer.len() as u64) as usize;
            stream.read_exact(&mut buffer[..read_len])?;
            file.write_all(&buffer[..read_len])?;
            remaining -= read_len as u64;
        }

        Ok(FileTransferDownloadSummary { byte_count })
    }
}

fn write_directory_entries(
    writer: &mut zip::ZipWriter<File>,
    directory_path: &Path,
    base_path: &Path,
    summary: &mut FileTransferArchiveSummary,
) -> Result<(), FileTransferError> {
    let mut children = std::fs::read_dir(directory_path)?.collect::<Result<Vec<_>, _>>()?;
    children.sort_by_key(|entry| entry.path());

    for child in children {
        let path = child.path();
        if path.is_dir() {
            write_directory_entries(writer, &path, base_path, summary)?;
            continue;
        }
        if path.is_file() {
            let entry_name = relative_zip_path(base_path, &path)?;
            write_file_entry(writer, &path, &entry_name, summary)?;
        }
    }

    Ok(())
}

fn write_file_entry(
    writer: &mut zip::ZipWriter<File>,
    file_path: &Path,
    entry_name: &str,
    summary: &mut FileTransferArchiveSummary,
) -> Result<(), FileTransferError> {
    writer.start_file(entry_name, SimpleFileOptions::default())?;

    let mut file = File::open(file_path)?;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let byte_count = file.read(&mut buffer)?;
        if byte_count == 0 {
            break;
        }
        writer.write_all(&buffer[..byte_count])?;
    }

    summary.file_count += 1;
    Ok(())
}

fn relative_zip_path(base_path: &Path, file_path: &Path) -> Result<String, FileTransferError> {
    let relative_path = file_path
        .strip_prefix(base_path)
        .map_err(|_| FileTransferError::InvalidField("source_path"))?;
    let entry_name = relative_path
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/");

    if entry_name.is_empty() || entry_name.starts_with('/') || entry_name.contains("..") {
        return Err(FileTransferError::InvalidField("source_path"));
    }

    Ok(entry_name)
}
