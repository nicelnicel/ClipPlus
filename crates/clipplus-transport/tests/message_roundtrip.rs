use clipplus_transport::file_transfer::{FileTransferError, FileTransferRequest, TransferState};
use clipplus_transport::message::{
    NativeClipboardMessage, NativeClipboardMessageError, NativeClipboardMessageKind,
    TransportMessage, TransportMessageError, TransportMessageKind,
};
use clipplus_transport::session::{HandshakeState, PeerSession, SessionError};
use serde_json::json;

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
fn native_clipboard_text_message_rejects_blank_required_fields() {
    let error = NativeClipboardMessage::text(" ", "mac-device", "Mac", "hello").unwrap_err();

    assert!(matches!(
        error,
        NativeClipboardMessageError::InvalidField("group_id")
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
