use std::collections::{BTreeSet, HashMap};
use std::fs::{File, OpenOptions};
use std::io::{ErrorKind, Read, Write};
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpListener, TcpStream, ToSocketAddrs};
#[cfg(windows)]
use std::os::windows::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use serde::{Deserialize, Serialize};
use thiserror::Error;
use zip::write::SimpleFileOptions;

const TREE_TRANSFER_REQUEST_PREFIX: &str = "tree:";

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
    #[error("file transfer json error: {0}")]
    Json(#[from] serde_json::Error),
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

    pub fn write_length_prefixed_zip<W: Write>(
        source_paths: &[PathBuf],
        archive_path: &Path,
        writer: &mut W,
    ) -> Result<FileTransferArchiveSummary, FileTransferError> {
        let summary = Self::write_zip(source_paths, archive_path)?;
        writer.write_all(&summary.byte_count.to_be_bytes())?;

        let mut archive = File::open(archive_path)?;
        let mut buffer = [0_u8; 64 * 1024];
        loop {
            let byte_count = archive.read(&mut buffer)?;
            if byte_count == 0 {
                break;
            }
            writer.write_all(&buffer[..byte_count])?;
        }

        Ok(summary)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct FileTransferTreeEntry {
    pub relative_path: String,
    pub byte_size: u64,
    pub is_directory: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileTransferTreeSummary {
    pub file_count: usize,
    pub byte_count: u64,
    /// Writer/server summaries return relative top-level paths; reader/download summaries return
    /// local paths under the destination staging directory.
    pub top_level_paths: Vec<PathBuf>,
}

pub struct FileTransferTree;

impl FileTransferTree {
    const MAX_MANIFEST_BYTES: u64 = 16 * 1024 * 1024;
    pub const MAX_FILE_BYTES: u64 = 512 * 1024 * 1024;
    pub const MAX_TREE_BYTES: u64 = 512 * 1024 * 1024;

    pub fn build_manifest(
        source_paths: &[PathBuf],
    ) -> Result<Vec<FileTransferTreeEntry>, FileTransferError> {
        Ok(Self::build_source_entries(source_paths)?
            .into_iter()
            .map(|source_entry| source_entry.entry)
            .collect())
    }

    pub fn write_length_prefixed_tree<W: Write>(
        source_paths: &[PathBuf],
        writer: &mut W,
    ) -> Result<FileTransferTreeSummary, FileTransferError> {
        let source_entries = Self::build_source_entries(source_paths)?;
        let manifest = source_entries
            .iter()
            .map(|source_entry| source_entry.entry.clone())
            .collect::<Vec<_>>();
        let summary = summarize_tree_manifest(&manifest, None)?;
        let manifest_json = serialize_tree_manifest(&manifest)?;
        writer.write_all(&(manifest_json.len() as u64).to_be_bytes())?;
        writer.write_all(&manifest_json)?;

        for source_entry in source_entries
            .iter()
            .filter(|source_entry| !source_entry.entry.is_directory)
        {
            let source_path = source_entry
                .source_path
                .as_deref()
                .ok_or(FileTransferError::InvalidField("source_path"))?;
            writer.write_all(&source_entry.entry.byte_size.to_be_bytes())?;
            write_file_bytes_exact(source_path, source_entry.entry.byte_size, writer)?;
        }

        Ok(summary)
    }

    pub fn read_length_prefixed_tree<R: Read>(
        reader: &mut R,
        staging_directory: &Path,
    ) -> Result<FileTransferTreeSummary, FileTransferError> {
        if staging_directory.exists() && !staging_directory.is_dir() {
            return Err(FileTransferError::InvalidField("staging_directory"));
        }

        let mut manifest_length_bytes = [0_u8; 8];
        reader.read_exact(&mut manifest_length_bytes)?;
        let manifest_length = u64::from_be_bytes(manifest_length_bytes);
        if manifest_length > Self::MAX_MANIFEST_BYTES {
            return Err(FileTransferError::InvalidField("manifest_size"));
        }

        let mut manifest_json = vec![0_u8; manifest_length as usize];
        reader.read_exact(&mut manifest_json)?;
        let manifest = serde_json::from_slice::<Vec<FileTransferTreeEntry>>(&manifest_json)?;
        let validated_entries = validate_tree_manifest(&manifest)?;

        let staging_existed = staging_directory.exists();
        std::fs::create_dir_all(staging_directory)?;

        let mut created_paths = Vec::new();
        let result = reject_existing_destination_paths(staging_directory, &validated_entries)
            .and_then(|()| {
                materialize_tree_entries(
                    reader,
                    staging_directory,
                    &validated_entries,
                    &mut created_paths,
                )
            });
        if let Err(error) = result {
            if !staging_existed {
                let _ = std::fs::remove_dir_all(staging_directory);
            } else {
                cleanup_created_tree_paths(&created_paths);
            }
            return Err(error);
        }

        summarize_tree_manifest(&manifest, Some(staging_directory))
    }

    fn build_source_entries(
        source_paths: &[PathBuf],
    ) -> Result<Vec<FileTransferTreeSourceEntry>, FileTransferError> {
        if source_paths.is_empty() {
            return Err(FileTransferError::InvalidField("source_paths"));
        }

        let mut entries = Vec::new();
        for source_path in source_paths {
            let base_path = source_path
                .parent()
                .ok_or(FileTransferError::InvalidField("source_path"))?;
            collect_tree_source_entries(source_path, base_path, &mut entries)?;
        }

        entries.sort_by(|left, right| left.entry.relative_path.cmp(&right.entry.relative_path));
        let manifest = entries
            .iter()
            .map(|entry| entry.entry.clone())
            .collect::<Vec<_>>();
        validate_tree_manifest(&manifest)?;

        Ok(entries)
    }
}

fn materialize_tree_entries<R: Read>(
    reader: &mut R,
    staging_directory: &Path,
    validated_entries: &[ValidatedFileTransferTreeEntry],
    created_paths: &mut Vec<CreatedTreePath>,
) -> Result<(), FileTransferError> {
    for validated_entry in validated_entries {
        let destination_path = staging_directory.join(&validated_entry.relative_path);
        if validated_entry.entry.is_directory {
            record_missing_directories(&destination_path, staging_directory, created_paths);
            std::fs::create_dir_all(&destination_path)?;
            continue;
        }

        if let Some(parent) = destination_path.parent() {
            record_missing_directories(parent, staging_directory, created_paths);
            std::fs::create_dir_all(parent)?;
        }

        let mut file_length_bytes = [0_u8; 8];
        reader.read_exact(&mut file_length_bytes)?;
        let file_length = u64::from_be_bytes(file_length_bytes);
        if file_length != validated_entry.entry.byte_size {
            return Err(FileTransferError::InvalidField("file_size"));
        }

        let mut file = create_new_tree_file(&destination_path)?;
        created_paths.push(CreatedTreePath::File(destination_path));
        copy_bytes_exact(reader, &mut file, file_length)?;
    }

    Ok(())
}

fn reject_existing_destination_paths(
    staging_directory: &Path,
    validated_entries: &[ValidatedFileTransferTreeEntry],
) -> Result<(), FileTransferError> {
    for validated_entry in validated_entries {
        if staging_directory
            .join(&validated_entry.relative_path)
            .try_exists()?
        {
            return Err(FileTransferError::InvalidField("destination_path"));
        }
    }

    Ok(())
}

fn create_new_tree_file(path: &Path) -> Result<File, FileTransferError> {
    OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(path)
        .map_err(|error| {
            if error.kind() == ErrorKind::AlreadyExists {
                FileTransferError::InvalidField("destination_path")
            } else {
                FileTransferError::Io(error)
            }
        })
}

#[derive(Debug, Clone)]
enum CreatedTreePath {
    Directory(PathBuf),
    File(PathBuf),
}

fn record_missing_directories(
    directory_path: &Path,
    staging_directory: &Path,
    created_paths: &mut Vec<CreatedTreePath>,
) {
    let mut missing_directories = Vec::new();
    let mut current_path = Some(directory_path);
    while let Some(path) = current_path {
        if path == staging_directory || !path.starts_with(staging_directory) {
            break;
        }
        if !path.exists() {
            missing_directories.push(path.to_path_buf());
        }
        current_path = path.parent();
    }

    for directory in missing_directories.into_iter().rev() {
        created_paths.push(CreatedTreePath::Directory(directory));
    }
}

fn cleanup_created_tree_paths(created_paths: &[CreatedTreePath]) {
    for created_path in created_paths.iter().rev() {
        match created_path {
            CreatedTreePath::Directory(path) => {
                let _ = std::fs::remove_dir(path);
            }
            CreatedTreePath::File(path) => {
                let _ = std::fs::remove_file(path);
            }
        }
    }
}

#[derive(Debug, Clone)]
struct FileTransferTreeSourceEntry {
    entry: FileTransferTreeEntry,
    source_path: Option<PathBuf>,
}

#[derive(Debug, Clone)]
struct ValidatedFileTransferTreeEntry {
    entry: FileTransferTreeEntry,
    relative_path: PathBuf,
}

pub struct FileTransferServer {
    listener: TcpListener,
    transfers: Mutex<HashMap<String, Vec<PathBuf>>>,
}

impl FileTransferServer {
    const ACCEPT_TIMEOUT: Duration = Duration::from_secs(5);
    const ACCEPT_POLL_INTERVAL: Duration = Duration::from_millis(25);

    pub fn bind(port: u16) -> Result<Self, FileTransferError> {
        let listener = TcpListener::bind(SocketAddr::V4(SocketAddrV4::new(
            Ipv4Addr::UNSPECIFIED,
            port,
        )))?;
        listener.set_nonblocking(true)?;

        Ok(Self {
            listener,
            transfers: Mutex::new(HashMap::new()),
        })
    }

    pub fn local_port(&self) -> Result<u16, FileTransferError> {
        Ok(self.listener.local_addr()?.port())
    }

    pub fn register_transfer(
        &self,
        transfer_id: &str,
        source_paths: Vec<PathBuf>,
    ) -> Result<(), FileTransferError> {
        let transfer_id = transfer_id.trim();
        if transfer_id.is_empty() {
            return Err(FileTransferError::InvalidField("transfer_id"));
        }
        if source_paths.is_empty() {
            return Err(FileTransferError::InvalidField("source_paths"));
        }

        self.transfers
            .lock()
            .map_err(|_| FileTransferError::InvalidField("transfer_registry"))?
            .insert(transfer_id.to_string(), source_paths);
        Ok(())
    }

    pub fn serve_next(
        &self,
        temp_dir: &Path,
    ) -> Result<FileTransferArchiveSummary, FileTransferError> {
        if !temp_dir.is_dir() {
            return Err(FileTransferError::InvalidField("temp_dir"));
        }
        let (mut stream, _) = self.accept_next_client()?;
        stream.set_nonblocking(false)?;
        stream.set_read_timeout(Some(Duration::from_secs(5)))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;
        let transfer_id = read_transfer_request_line(&mut stream)?;
        let source_paths = self
            .transfers
            .lock()
            .map_err(|_| FileTransferError::InvalidField("transfer_registry"))?
            .get(&transfer_id)
            .cloned()
            .ok_or(FileTransferError::InvalidField("transfer_id"))?;

        let archive_path = temp_dir.join(format!("ClipPlus-{}.zip", uuid::Uuid::new_v4()));
        let result = FileTransferArchive::write_length_prefixed_zip(
            &source_paths,
            &archive_path,
            &mut stream,
        );
        let _ = std::fs::remove_file(&archive_path);

        result
    }

    pub fn serve_next_tree(&self) -> Result<FileTransferTreeSummary, FileTransferError> {
        let (mut stream, _) = self.accept_next_client()?;
        stream.set_nonblocking(false)?;
        stream.set_read_timeout(Some(Duration::from_secs(5)))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;
        let transfer_id = read_tree_transfer_request_line(&mut stream)?;
        let source_paths = self
            .transfers
            .lock()
            .map_err(|_| FileTransferError::InvalidField("transfer_registry"))?
            .get(&transfer_id)
            .cloned()
            .ok_or(FileTransferError::InvalidField("transfer_id"))?;

        FileTransferTree::write_length_prefixed_tree(&source_paths, &mut stream)
    }

    fn accept_next_client(&self) -> Result<(TcpStream, SocketAddr), FileTransferError> {
        let started_at = std::time::Instant::now();
        loop {
            match self.listener.accept() {
                Ok(client) => return Ok(client),
                Err(error)
                    if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut)
                        && started_at.elapsed() < Self::ACCEPT_TIMEOUT =>
                {
                    std::thread::sleep(Self::ACCEPT_POLL_INTERVAL);
                }
                Err(error) => return Err(FileTransferError::Io(error)),
            }
        }
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

    pub fn download_tree_to_directory(
        host: &str,
        port: u16,
        transfer_id: &str,
        destination_directory: &Path,
    ) -> Result<FileTransferTreeSummary, FileTransferError> {
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
        if destination_directory.exists() && !destination_directory.is_dir() {
            return Err(FileTransferError::InvalidField("destination_directory"));
        }

        let target = (host, port)
            .to_socket_addrs()?
            .next()
            .ok_or(FileTransferError::InvalidField("host"))?;
        let mut stream = TcpStream::connect_timeout(&target, Duration::from_secs(5))?;
        stream.set_read_timeout(Some(Duration::from_secs(30)))?;
        stream.set_write_timeout(Some(Duration::from_secs(30)))?;
        stream.write_all(TREE_TRANSFER_REQUEST_PREFIX.as_bytes())?;
        stream.write_all(transfer_id.as_bytes())?;
        stream.write_all(b"\n")?;

        FileTransferTree::read_length_prefixed_tree(&mut stream, destination_directory)
    }
}

fn read_tree_transfer_request_line(stream: &mut TcpStream) -> Result<String, FileTransferError> {
    let request = read_transfer_request_line(stream)?;
    let Some(transfer_id) = request.strip_prefix(TREE_TRANSFER_REQUEST_PREFIX) else {
        return Err(FileTransferError::InvalidField("transfer_request"));
    };
    if transfer_id.trim().is_empty() || transfer_id != transfer_id.trim() {
        return Err(FileTransferError::InvalidField("transfer_request"));
    }

    Ok(transfer_id.to_string())
}

fn read_transfer_request_line(stream: &mut TcpStream) -> Result<String, FileTransferError> {
    let mut bytes = Vec::new();
    let mut byte = [0_u8; 1];
    loop {
        let read_count = stream.read(&mut byte)?;
        if read_count == 0 {
            break;
        }
        if byte[0] == b'\n' {
            break;
        }
        bytes.push(byte[0]);
        if bytes.len() > 1024 {
            return Err(FileTransferError::InvalidField("transfer_id"));
        }
    }

    let transfer_id =
        String::from_utf8(bytes).map_err(|_| FileTransferError::InvalidField("transfer_id"))?;
    let transfer_id = transfer_id.trim().to_string();
    if transfer_id.is_empty() {
        return Err(FileTransferError::InvalidField("transfer_id"));
    }

    Ok(transfer_id)
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

fn collect_tree_source_entries(
    path: &Path,
    base_path: &Path,
    entries: &mut Vec<FileTransferTreeSourceEntry>,
) -> Result<(), FileTransferError> {
    let metadata = source_path_metadata(path)?;
    let relative_path = relative_tree_path(base_path, path)?;

    if metadata.is_dir() {
        entries.push(FileTransferTreeSourceEntry {
            entry: FileTransferTreeEntry {
                relative_path,
                byte_size: 0,
                is_directory: true,
            },
            source_path: None,
        });

        let mut children = std::fs::read_dir(path)?.collect::<Result<Vec<_>, _>>()?;
        children.sort_by_key(|entry| entry.path());
        for child in children {
            collect_tree_source_entries(&child.path(), base_path, entries)?;
        }

        return Ok(());
    }

    if metadata.is_file() {
        entries.push(FileTransferTreeSourceEntry {
            entry: FileTransferTreeEntry {
                relative_path,
                byte_size: metadata.len(),
                is_directory: false,
            },
            source_path: Some(path.to_path_buf()),
        });
        return Ok(());
    }

    Err(FileTransferError::InvalidField("source_path"))
}

fn source_path_metadata(path: &Path) -> Result<std::fs::Metadata, FileTransferError> {
    let metadata = std::fs::symlink_metadata(path).map_err(|error| {
        if error.kind() == ErrorKind::NotFound {
            FileTransferError::InvalidField("source_path")
        } else {
            FileTransferError::Io(error)
        }
    })?;
    if metadata.file_type().is_symlink() {
        return Err(FileTransferError::InvalidField("source_path"));
    }
    #[cfg(windows)]
    {
        const FILE_ATTRIBUTE_REPARSE_POINT: u32 = 0x400;
        if metadata.file_attributes() & FILE_ATTRIBUTE_REPARSE_POINT != 0 {
            return Err(FileTransferError::InvalidField("source_path"));
        }
    }

    Ok(metadata)
}

fn relative_tree_path(base_path: &Path, file_path: &Path) -> Result<String, FileTransferError> {
    let relative_path = file_path
        .strip_prefix(base_path)
        .map_err(|_| FileTransferError::InvalidField("source_path"))?;
    let entry_name = relative_path
        .components()
        .map(|component| component.as_os_str().to_string_lossy())
        .collect::<Vec<_>>()
        .join("/");

    normalize_safe_tree_relative_path(&entry_name)
}

fn validate_tree_manifest(
    manifest: &[FileTransferTreeEntry],
) -> Result<Vec<ValidatedFileTransferTreeEntry>, FileTransferError> {
    let mut total_byte_size = 0_u64;
    let mut folded_paths = BTreeSet::new();
    let validated_entries = manifest
        .iter()
        .map(|entry| {
            let relative_path = normalize_safe_tree_relative_path(&entry.relative_path)?;
            let folded_path = fold_tree_relative_path(&relative_path);
            if !folded_paths.insert(folded_path) {
                return Err(FileTransferError::InvalidField("relative_path"));
            }
            if entry.is_directory && entry.byte_size != 0 {
                return Err(FileTransferError::InvalidField("byte_size"));
            }
            if !entry.is_directory {
                if entry.byte_size > FileTransferTree::MAX_FILE_BYTES {
                    return Err(FileTransferError::InvalidField("byte_size"));
                }
                total_byte_size = total_byte_size
                    .checked_add(entry.byte_size)
                    .filter(|byte_size| *byte_size <= FileTransferTree::MAX_TREE_BYTES)
                    .ok_or(FileTransferError::InvalidField("tree_size"))?;
            }

            Ok(ValidatedFileTransferTreeEntry {
                entry: FileTransferTreeEntry {
                    relative_path: relative_path.clone(),
                    byte_size: entry.byte_size,
                    is_directory: entry.is_directory,
                },
                relative_path: normalized_tree_path_buf(&relative_path),
            })
        })
        .collect::<Result<Vec<_>, _>>()?;

    reject_file_ancestor_conflicts(&validated_entries)?;

    Ok(validated_entries)
}

fn summarize_tree_manifest(
    manifest: &[FileTransferTreeEntry],
    top_level_base: Option<&Path>,
) -> Result<FileTransferTreeSummary, FileTransferError> {
    let validated_entries = validate_tree_manifest(manifest)?;
    let mut top_level_paths = BTreeSet::new();
    let mut file_count = 0;
    let mut byte_count = 0;

    for validated_entry in validated_entries {
        if !validated_entry.entry.is_directory {
            file_count += 1;
            byte_count += validated_entry.entry.byte_size;
        }

        let top_level_name = validated_entry
            .entry
            .relative_path
            .split('/')
            .next()
            .ok_or(FileTransferError::InvalidField("relative_path"))?;
        let top_level_path = normalized_tree_path_buf(top_level_name);
        top_level_paths.insert(match top_level_base {
            Some(base) => base.join(top_level_path),
            None => top_level_path,
        });
    }

    Ok(FileTransferTreeSummary {
        file_count,
        byte_count,
        top_level_paths: top_level_paths.into_iter().collect(),
    })
}

fn serialize_tree_manifest(
    manifest: &[FileTransferTreeEntry],
) -> Result<Vec<u8>, FileTransferError> {
    let manifest_json = serde_json::to_vec(manifest)?;
    if manifest_json.len() as u64 > FileTransferTree::MAX_MANIFEST_BYTES {
        return Err(FileTransferError::InvalidField("manifest_size"));
    }

    Ok(manifest_json)
}

fn normalize_safe_tree_relative_path(value: &str) -> Result<String, FileTransferError> {
    let normalized = value.replace('\\', "/");
    if normalized.is_empty()
        || normalized.starts_with('/')
        || normalized.contains(':')
        || normalized.contains('\0')
    {
        return Err(FileTransferError::InvalidField("relative_path"));
    }

    for component in normalized.split('/') {
        if !is_safe_tree_path_component(component) {
            return Err(FileTransferError::InvalidField("relative_path"));
        }
    }

    Ok(normalized)
}

fn is_safe_tree_path_component(component: &str) -> bool {
    !component.is_empty()
        && component != "."
        && component != ".."
        && !component.ends_with(' ')
        && !component.ends_with('.')
        && !is_windows_reserved_device_name(component)
}

fn is_windows_reserved_device_name(component: &str) -> bool {
    let stem = component.split('.').next().unwrap_or(component);
    let upper_stem = stem.to_ascii_uppercase();

    matches!(upper_stem.as_str(), "CON" | "PRN" | "AUX" | "NUL")
        || upper_stem.strip_prefix("COM").is_some_and(|suffix| {
            matches!(suffix, "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9")
        })
        || upper_stem.strip_prefix("LPT").is_some_and(|suffix| {
            matches!(suffix, "1" | "2" | "3" | "4" | "5" | "6" | "7" | "8" | "9")
        })
}

fn reject_file_ancestor_conflicts(
    entries: &[ValidatedFileTransferTreeEntry],
) -> Result<(), FileTransferError> {
    let file_paths = entries
        .iter()
        .filter(|entry| !entry.entry.is_directory)
        .map(|entry| fold_tree_relative_path(&entry.entry.relative_path))
        .collect::<BTreeSet<_>>();

    for entry in entries {
        let mut components = entry.entry.relative_path.split('/').collect::<Vec<_>>();
        while components.len() > 1 {
            components.pop();
            let ancestor = components.join("/");
            if file_paths.contains(&fold_tree_relative_path(&ancestor)) {
                return Err(FileTransferError::InvalidField("relative_path"));
            }
        }
    }

    Ok(())
}

fn fold_tree_relative_path(value: &str) -> String {
    value.to_lowercase()
}

fn normalized_tree_path_buf(value: &str) -> PathBuf {
    value.split('/').collect()
}

fn write_file_bytes_exact<W: Write>(
    file_path: &Path,
    byte_count: u64,
    writer: &mut W,
) -> Result<(), FileTransferError> {
    let metadata = source_path_metadata(file_path)?;
    if !metadata.is_file() || metadata.len() != byte_count {
        return Err(FileTransferError::InvalidField("source_path"));
    }
    let mut file = File::open(file_path)?;
    copy_bytes_exact(&mut file, writer, byte_count)
}

fn copy_bytes_exact<R: Read, W: Write>(
    reader: &mut R,
    writer: &mut W,
    byte_count: u64,
) -> Result<(), FileTransferError> {
    let mut remaining = byte_count;
    let mut buffer = [0_u8; 64 * 1024];
    while remaining > 0 {
        let read_len = remaining.min(buffer.len() as u64) as usize;
        reader.read_exact(&mut buffer[..read_len])?;
        writer.write_all(&buffer[..read_len])?;
        remaining -= read_len as u64;
    }

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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn serialize_tree_manifest_rejects_reader_incompatible_manifest_size() {
        let manifest = vec![FileTransferTreeEntry {
            relative_path: "a".repeat(FileTransferTree::MAX_MANIFEST_BYTES as usize + 1),
            byte_size: 0,
            is_directory: true,
        }];

        let result = serialize_tree_manifest(&manifest);

        assert!(matches!(
            result,
            Err(FileTransferError::InvalidField("manifest_size"))
        ));
    }
}
