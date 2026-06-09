use clipplus_transport::file_transfer::{FileTransferRequest, TransferState};
use clipplus_transport::message::{TransportMessage, TransportMessageKind};
use clipplus_transport::session::{HandshakeState, PeerSession};
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
    let error = TransportMessage::from_json("not-json").unwrap_err();

    assert!(format!("{error}").contains("expected"));
}

#[test]
fn transport_message_rejects_empty_sender_device_id() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.sender_device_id.clear();
    let json = message.to_json().unwrap();

    let error = TransportMessage::from_json(&json).unwrap_err();

    assert!(format!("{error}").contains("sender_device_id"));
}

#[test]
fn transport_message_rejects_non_json_payload_json() {
    let mut message = TransportMessage::new_for_test(TransportMessageKind::TextEvent);
    message.payload_json = "plain text".to_string();
    let json = message.to_json().unwrap();

    let error = TransportMessage::from_json(&json).unwrap_err();

    assert!(format!("{error}").contains("payload_json"));
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
fn file_transfer_request_has_expiry() {
    let request = FileTransferRequest::new_for_test("transfer-a", 30);

    assert_eq!(request.state, TransferState::Available);
    assert!(!request.is_expired_at_minute(29));
    assert!(!request.is_expired_at_minute(30));
    assert!(request.is_expired_at_minute(31));
}
