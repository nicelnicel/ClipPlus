use clipplus_transport::file_transfer::{
    FileTransferArchive, FileTransferDownload, FileTransferError, FileTransferRequest,
    TransferState,
};
use clipplus_transport::message::{
    NativeClipboardMessage, NativeClipboardMessageError, NativeClipboardMessageKind,
    NativeFileTransferItem, TransportMessage, TransportMessageError, TransportMessageKind,
};
use clipplus_transport::session::{HandshakeState, PeerSession, SessionError};
use serde_json::json;
use std::io::{BufRead, Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::thread;

#[test]
fn transport_message_roundtrips_json() {
    let message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);

    let json = message.to_json().unwrap();
    let decoded = TransportMessage::from_json(&json).unwrap();

    assert_eq!(decoded.kind, TransportMessageKind::TextEvent);
}

#[test]
fn transport_message_kind_uses_snake_case_wire_value() {
    let message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);

    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("text_event"));
}

#[test]
fn transport_message_rejects_invalid_json() {
    let error = TransportMessage::from_json("not-json");

    assert!(matches!(error, Err(TransportMessageError::Json(_))));
}

#[test]
fn transport_message_rejects_empty_sender_device_id() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.sender_device_id.clear();
    let json = serde_json::to_string(&message).unwrap();

    let error = TransportMessage::from_json(&json).unwrap_err();

    assert!(matches!(
        error,
        TransportMessageError::InvalidField("sender_device_id")
    ));
}

#[test]
fn transport_message_rejects_non_json_payload_json() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.payload_json = "plain text".to_string();
    let json = serde_json::to_string(&message).unwrap();

    let error = TransportMessage::from_json(&json).unwrap_err();

    assert!(matches!(
        error,
        TransportMessageError::InvalidField("payload_json")
    ));
}

#[test]
fn transport_message_to_json_rejects_empty_sender_device_id() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.sender_device_id.clear();

    let error = message.to_json();

    assert!(matches!(
        error,
        Err(TransportMessageError::InvalidField("sender_device_id"))
    ));
}

#[test]
fn transport_message_to_json_rejects_non_json_payload_json() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.payload_json = "plain text".to_string();

    let error = message.to_json();

    assert!(matches!(
        error,
        Err(TransportMessageError::InvalidField("payload_json"))
    ));
}

#[test]
fn transport_message_unknown_kind_is_rejected() {
    let message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    let mut encoded: serde_json::Value = serde_json::from_str(&message.to_json().unwrap()).unwrap();
    encoded["kind"] = json!("future_kind");
    let json = serde_json::to_string(&encoded).unwrap();

    let error = TransportMessage::from_json(&json);

    assert!(matches!(error, Err(TransportMessageError::Json(_))));
}

#[test]
fn native_clipboard_text_message_uses_current_shell_wire_format() {
    let message =
        NativeClipboardMessage::text("group-1", "mac-device", "Mac", "hello from rust transport")
            .unwrap();
    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("text"));
    assert_eq!(encoded["protocolVersion"], json!(1));
    assert_eq!(encoded["groupId"], json!("group-1"));
    assert_eq!(encoded["senderDeviceId"], json!("mac-device"));
    assert_eq!(encoded["senderDeviceName"], json!("Mac"));
    assert_eq!(encoded["text"], json!("hello from rust transport"));
    assert!(encoded["eventId"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    assert!(encoded["createdAt"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));

    let decoded = NativeClipboardMessage::from_json(&json).unwrap();
    assert_eq!(decoded.kind, NativeClipboardMessageKind::Text);
    assert_eq!(decoded.text.as_deref(), Some("hello from rust transport"));
}

#[test]
fn native_clipboard_hello_message_uses_current_shell_wire_format() {
    let message = NativeClipboardMessage::hello("group-1", "mac-device", "Mac").unwrap();
    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("hello"));
    assert_eq!(encoded["protocolVersion"], json!(1));
    assert_eq!(encoded["groupId"], json!("group-1"));
    assert_eq!(encoded["senderDeviceId"], json!("mac-device"));
    assert_eq!(encoded["senderDeviceName"], json!("Mac"));
    assert!(encoded.get("text").is_none());

    let decoded = NativeClipboardMessage::from_json(&json).unwrap();
    assert_eq!(decoded.kind, NativeClipboardMessageKind::Hello);
}

#[test]
fn native_clipboard_trust_message_uses_current_shell_wire_format() {
    let message =
        NativeClipboardMessage::trust("group-1", "mac-device", "Mac", "windows-device").unwrap();
    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("trust"));
    assert_eq!(encoded["protocolVersion"], json!(1));
    assert_eq!(encoded["groupId"], json!("group-1"));
    assert_eq!(encoded["senderDeviceId"], json!("mac-device"));
    assert_eq!(encoded["approvedDeviceId"], json!("windows-device"));

    let decoded = NativeClipboardMessage::from_json(&json).unwrap();
    assert_eq!(decoded.kind, NativeClipboardMessageKind::Trust);
    assert_eq!(
        decoded.approved_device_id.as_deref(),
        Some("windows-device")
    );
}

#[test]
fn native_clipboard_image_message_uses_current_shell_wire_format() {
    let png_bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    let message =
        NativeClipboardMessage::image("group-1", "mac-device", "Mac", &png_bytes).unwrap();
    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("image"));
    assert_eq!(encoded["protocolVersion"], json!(1));
    assert_eq!(encoded["groupId"], json!("group-1"));
    assert_eq!(encoded["senderDeviceId"], json!("mac-device"));
    assert_eq!(encoded["imageBase64"], json!("iVBORw0KGgo="));
    assert_eq!(encoded["imageByteSize"], json!(8));
    assert_eq!(
        encoded["imageContentHash"],
        json!("4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6")
    );
    assert!(encoded.get("text").is_none());

    let decoded = NativeClipboardMessage::from_json(&json).unwrap();
    assert_eq!(decoded.kind, NativeClipboardMessageKind::Image);
    assert_eq!(decoded.image_byte_size, Some(8));
}

#[test]
fn native_clipboard_file_offer_message_uses_current_shell_wire_format() {
    let files = vec![
        NativeFileTransferItem {
            relative_path: "Reports/Q1.txt".to_string(),
            byte_size: 12,
            is_directory: false,
        },
        NativeFileTransferItem {
            relative_path: "Screenshots".to_string(),
            byte_size: 34,
            is_directory: true,
        },
    ];
    let message = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        files.clone(),
        47_632,
    )
    .unwrap();
    let json = message.to_json().unwrap();
    let encoded: serde_json::Value = serde_json::from_str(&json).unwrap();

    assert_eq!(encoded["kind"], json!("fileOffer"));
    assert_eq!(encoded["protocolVersion"], json!(1));
    assert_eq!(encoded["groupId"], json!("group-1"));
    assert_eq!(encoded["senderDeviceId"], json!("mac-device"));
    assert_eq!(encoded["transferId"], json!("transfer-1"));
    assert_eq!(encoded["archivePort"], json!(47_632));
    assert_eq!(encoded["files"][0]["relativePath"], json!("Reports/Q1.txt"));
    assert_eq!(encoded["files"][0]["byteSize"], json!(12));
    assert_eq!(encoded["files"][0]["isDirectory"], json!(false));
    assert_eq!(encoded["files"][1]["relativePath"], json!("Screenshots"));
    assert_eq!(encoded["files"][1]["isDirectory"], json!(true));
    assert!(encoded.get("text").is_none());
    assert!(encoded.get("imageBase64").is_none());
    assert!(json.contains("Reports/Q1.txt"));
    assert!(!json.contains("/Users/"));
    assert!(!json.contains("C:\\"));

    let decoded = NativeClipboardMessage::from_json(&json).unwrap();
    assert_eq!(decoded.kind, NativeClipboardMessageKind::FileOffer);
    assert_eq!(decoded.transfer_id.as_deref(), Some("transfer-1"));
    assert_eq!(decoded.files.as_deref(), Some(files.as_slice()));
}

#[test]
fn native_clipboard_file_offer_message_rejects_invalid_values() {
    let valid_files = vec![NativeFileTransferItem {
        relative_path: "Reports/Q1.txt".to_string(),
        byte_size: 12,
        is_directory: false,
    }];
    let blank_transfer = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        " ",
        valid_files.clone(),
        47_632,
    )
    .unwrap_err();
    let empty_files = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        vec![],
        47_632,
    )
    .unwrap_err();
    let zero_port = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        valid_files.clone(),
        0,
    )
    .unwrap_err();
    let absolute_path = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        vec![NativeFileTransferItem {
            relative_path: "/Users/cc/private.txt".to_string(),
            byte_size: 12,
            is_directory: false,
        }],
        47_632,
    )
    .unwrap_err();
    let traversal_path = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        vec![NativeFileTransferItem {
            relative_path: "../private.txt".to_string(),
            byte_size: 12,
            is_directory: false,
        }],
        47_632,
    )
    .unwrap_err();
    let windows_path = NativeClipboardMessage::file_offer(
        "group-1",
        "mac-device",
        "Mac",
        "transfer-1",
        vec![NativeFileTransferItem {
            relative_path: r"C:\Users\cc\private.txt".to_string(),
            byte_size: 12,
            is_directory: false,
        }],
        47_632,
    )
    .unwrap_err();

    assert!(matches!(
        blank_transfer,
        NativeClipboardMessageError::InvalidField("transfer_id")
    ));
    assert!(matches!(
        empty_files,
        NativeClipboardMessageError::InvalidField("files")
    ));
    assert!(matches!(
        zero_port,
        NativeClipboardMessageError::InvalidField("archive_port")
    ));
    assert!(matches!(
        absolute_path,
        NativeClipboardMessageError::InvalidField("relative_path")
    ));
    assert!(matches!(
        traversal_path,
        NativeClipboardMessageError::InvalidField("relative_path")
    ));
    assert!(matches!(
        windows_path,
        NativeClipboardMessageError::InvalidField("relative_path")
    ));
}

#[test]
fn native_clipboard_text_message_rejects_blank_required_fields() {
    let error = NativeClipboardMessage::text(" ", "mac-device", "Mac", "hello").unwrap_err();

    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("group_id")
    ));
}

#[test]
fn native_clipboard_image_message_rejects_empty_and_oversized_payloads() {
    let empty = NativeClipboardMessage::image("group-1", "mac-device", "Mac", &[]).unwrap_err();
    let oversized = vec![0xFF; NativeClipboardMessage::MAX_INLINE_IMAGE_BYTES + 1];
    let oversized =
        NativeClipboardMessage::image("group-1", "mac-device", "Mac", &oversized).unwrap_err();

    assert!(matches!(
        empty,
        NativeClipboardMessageError::InvalidField("image_bytes")
    ));
    assert!(matches!(
        oversized,
        NativeClipboardMessageError::InvalidField("image_byte_size")
    ));
}

#[test]
fn native_clipboard_image_message_allows_exact_inline_limit() {
    let payload = vec![0xAA; NativeClipboardMessage::MAX_INLINE_IMAGE_BYTES];
    let message = NativeClipboardMessage::image("group-1", "mac-device", "Mac", &payload).unwrap();

    assert_eq!(
        message.image_byte_size,
        Some(NativeClipboardMessage::MAX_INLINE_IMAGE_BYTES)
    );
}

#[test]
fn native_clipboard_image_message_rejects_tampered_metadata() {
    let png_bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    let message =
        NativeClipboardMessage::image("group-1", "mac-device", "Mac", &png_bytes).unwrap();

    let mut encoded: serde_json::Value = serde_json::from_str(&message.to_json().unwrap()).unwrap();
    encoded["imageByteSize"] = json!(9);
    let error =
        NativeClipboardMessage::from_json(&serde_json::to_string(&encoded).unwrap()).unwrap_err();
    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("image_byte_size")
    ));

    let mut encoded: serde_json::Value = serde_json::from_str(&message.to_json().unwrap()).unwrap();
    encoded["imageContentHash"] = json!("bad");
    let error =
        NativeClipboardMessage::from_json(&serde_json::to_string(&encoded).unwrap()).unwrap_err();
    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("image_content_hash")
    ));

    let mut encoded: serde_json::Value = serde_json::from_str(&message.to_json().unwrap()).unwrap();
    encoded["imageBase64"] = json!("not base64");
    let error =
        NativeClipboardMessage::from_json(&serde_json::to_string(&encoded).unwrap()).unwrap_err();
    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("image_base64")
    ));
}

#[test]
fn native_clipboard_trust_message_rejects_blank_approved_device_id() {
    let error = NativeClipboardMessage::trust("group-1", "mac-device", "Mac", " ").unwrap_err();

    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("approved_device_id")
    ));
}

#[test]
fn peer_session_requires_trust_before_sync() {
    let session = PeerSession::new("device-a", HandshakeState::PendingApproval);

    assert!(!session.can_sync());
}

#[test]
fn peer_session_allows_sync_only_when_trusted() {
    let trusted = PeerSession::new("device-a", HandshakeState::Trusted);
    let rejected = PeerSession::new("device-b", HandshakeState::Rejected);
    let key_mismatch = PeerSession::new("device-c", HandshakeState::KeyMismatch);

    assert!(trusted.can_sync());
    assert!(!rejected.can_sync());
    assert!(!key_mismatch.can_sync());
}

#[test]
fn peer_session_rejects_blank_device_id() {
    let session = PeerSession::try_new("   ", HandshakeState::Trusted);

    assert!(matches!(
        session,
        Err(SessionError::InvalidField("device_id"))
    ));
}

#[test]
fn peer_session_trims_device_id_on_new() {
    let session = PeerSession::new(" device-a ", HandshakeState::Trusted);

    assert_eq!(session.device_id, "device-a");
    assert!(session.can_sync());
}

#[test]
fn peer_session_can_sync_defends_against_blank_public_device_id() {
    let session = PeerSession {
        device_id: String::new(),
        state: HandshakeState::Trusted,
    };

    assert!(!session.can_sync());
}

#[test]
fn file_transfer_request_has_expiry() {
    let request = FileTransferRequest::new_for_test("transfer-a", 30);

    assert_eq!(request.state, TransferState::Available);
    assert!(!request.is_expired_at_minute(29));
    assert!(!request.is_expired_at_minute(30));
    assert!(request.is_expired_at_minute(31));
}

#[test]
fn file_transfer_request_supports_u64_expiry_minutes() {
    let expires_after_minutes = u32::MAX as u64 + 10;
    let request = FileTransferRequest::new_for_test("transfer-long", expires_after_minutes);

    assert!(!request.is_expired_at_minute(u32::MAX as u64 + 9));
    assert!(request.is_expired_at_minute(u32::MAX as u64 + 11));
}

#[test]
fn file_transfer_request_rejects_blank_transfer_id() {
    let request = FileTransferRequest::new("   ", 30);

    assert!(matches!(
        request,
        Err(FileTransferError::InvalidField("transfer_id"))
    ));
}

#[test]
fn file_transfer_request_trims_transfer_id_on_new() {
    let request = FileTransferRequest::new(" transfer-a ", 30).unwrap();

    assert_eq!(request.transfer_id, "transfer-a");
    assert_eq!(request.state, TransferState::Available);
}

#[test]
fn file_transfer_archive_writes_zip_entries_for_files_and_directories() {
    let temporary_directory = unique_temp_dir();
    let source_directory = temporary_directory.join("source");
    let nested_directory = source_directory.join("Nested");
    std::fs::create_dir_all(&nested_directory).unwrap();
    std::fs::write(source_directory.join("a.txt"), "alpha").unwrap();
    std::fs::write(nested_directory.join("b.txt"), "beta").unwrap();
    let archive_path = temporary_directory.join("files.zip");

    let summary = FileTransferArchive::write_zip(
        &[source_directory.join("a.txt"), nested_directory.clone()],
        &archive_path,
    )
    .unwrap();

    let entries = read_zip_entries(&archive_path);
    assert_eq!(summary.file_count, 2);
    assert!(summary.byte_count > 0);
    assert_eq!(
        entries,
        vec![
            ("Nested/b.txt".to_string(), "beta".to_string()),
            ("a.txt".to_string(), "alpha".to_string()),
        ]
    );
}

#[test]
fn file_transfer_archive_rejects_empty_sources_and_missing_parent() {
    let temporary_directory = unique_temp_dir();
    let missing_parent_archive = temporary_directory.join("missing").join("files.zip");

    let empty_sources = FileTransferArchive::write_zip(&[], &temporary_directory.join("empty.zip"));
    let missing_parent = FileTransferArchive::write_zip(
        &[temporary_directory.join("source.txt")],
        &missing_parent_archive,
    );

    assert!(matches!(
        empty_sources,
        Err(FileTransferError::InvalidField("source_paths"))
    ));
    assert!(matches!(
        missing_parent,
        Err(FileTransferError::InvalidField("archive_parent"))
    ));
}

#[test]
fn file_transfer_download_writes_length_prefixed_archive_from_tcp_server() {
    let temporary_directory = unique_temp_dir();
    let destination_path = temporary_directory.join("received.zip");
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
        let mut transfer_id = String::new();
        reader.read_line(&mut transfer_id).unwrap();
        assert_eq!(transfer_id.trim(), "transfer-a");

        let payload = b"zip-bytes-from-server";
        stream
            .write_all(&(payload.len() as u64).to_be_bytes())
            .unwrap();
        stream.write_all(payload).unwrap();
    });

    let summary =
        FileTransferDownload::download_to_path("127.0.0.1", port, "transfer-a", &destination_path)
            .unwrap();
    server.join().unwrap();

    assert_eq!(summary.byte_count, 21);
    assert_eq!(
        std::fs::read(destination_path).unwrap(),
        b"zip-bytes-from-server"
    );
}

#[test]
fn file_transfer_download_rejects_invalid_fields() {
    let temporary_directory = unique_temp_dir();
    let destination_path = temporary_directory.join("received.zip");

    assert!(matches!(
        FileTransferDownload::download_to_path("", 47_632, "transfer-a", &destination_path),
        Err(FileTransferError::InvalidField("host"))
    ));
    assert!(matches!(
        FileTransferDownload::download_to_path("127.0.0.1", 0, "transfer-a", &destination_path),
        Err(FileTransferError::InvalidField("port"))
    ));
    assert!(matches!(
        FileTransferDownload::download_to_path("127.0.0.1", 47_632, "   ", &destination_path),
        Err(FileTransferError::InvalidField("transfer_id"))
    ));
    assert!(matches!(
        FileTransferDownload::download_to_path(
            "127.0.0.1",
            47_632,
            "transfer-a",
            &temporary_directory.join("missing").join("received.zip")
        ),
        Err(FileTransferError::InvalidField("destination_parent"))
    ));
}

fn unique_temp_dir() -> PathBuf {
    let path = std::env::temp_dir().join(format!("clipplus-{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn read_zip_entries(path: &Path) -> Vec<(String, String)> {
    let file = std::fs::File::open(path).unwrap();
    let mut archive = zip::ZipArchive::new(file).unwrap();
    let mut entries = Vec::new();

    for index in 0..archive.len() {
        let mut file = archive.by_index(index).unwrap();
        if file.is_dir() {
            continue;
        }
        let mut contents = String::new();
        file.read_to_string(&mut contents).unwrap();
        entries.push((file.name().to_string(), contents));
    }

    entries.sort_by(|left, right| left.0.cmp(&right.0));
    entries
}
