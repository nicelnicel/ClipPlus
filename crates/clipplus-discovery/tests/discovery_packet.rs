use clipplus_discovery::packet::{DiscoveryPacket, DiscoveryPacketError, PeerCapability};
use clipplus_discovery::udp::{
    DiscoveryDatagram, DiscoverySocketConfig, DiscoveryUdpSocket, DISCOVERY_BROADCAST,
    DISCOVERY_PORT,
};
use serde_json::{json, Value};
use std::collections::BTreeSet;
use std::net::{Ipv4Addr, SocketAddrV4};
use tokio::time::{timeout, Duration};

#[test]
fn discovery_packet_roundtrips_json() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    let json = packet.to_json().unwrap();
    let decoded = DiscoveryPacket::from_json(&json).unwrap();

    assert_eq!(decoded.group_id, "group-a");
    assert_eq!(decoded.device_id, "device-a");
    assert_eq!(
        decoded.capabilities,
        vec![
            PeerCapability::Text,
            PeerCapability::Image,
            PeerCapability::File
        ]
    );
}

#[test]
fn packet_json_uses_stable_wire_values() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    let json = packet.to_json().unwrap();
    let value: Value = serde_json::from_str(&json).unwrap();
    let object = value.as_object().unwrap();
    let actual_fields = object.keys().map(String::as_str).collect::<BTreeSet<_>>();
    let expected_fields = BTreeSet::from([
        "app_version",
        "capabilities",
        "device_id",
        "device_name",
        "group_id",
        "platform",
        "public_key",
    ]);

    assert_eq!(actual_fields, expected_fields);
    assert_eq!(
        object.get("capabilities").unwrap(),
        &json!(["text", "image", "file"])
    );
    for forbidden_field in ["raw_key", "shared_key", "verifier", "private_key"] {
        assert!(!object.contains_key(forbidden_field));
    }
    for canary in ["raw-secret-key", "private-secret-key"] {
        assert!(!json.contains(canary));
    }
}

#[test]
fn unknown_capability_is_preserved() {
    let json = r#"{
        "group_id": "group-a",
        "device_id": "device-a",
        "device_name": "Device A",
        "platform": "macos",
        "public_key": "public-key",
        "app_version": "1.0.0",
        "capabilities": ["text", "clipboard_history"]
    }"#;

    let packet = DiscoveryPacket::from_json(json).unwrap();

    assert!(packet.capabilities.contains(&PeerCapability::Text));
    assert!(packet
        .capabilities
        .contains(&PeerCapability::Unknown("clipboard_history".into())));
}

#[test]
fn group_mismatch_is_rejected() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    assert!(!packet.matches_group("group-b"));
    assert!(packet.matches_group("group-a"));
}

#[test]
fn empty_group_never_matches() {
    let mut packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    assert!(!packet.matches_group(""));

    packet.group_id.clear();
    assert!(!packet.matches_group("group-a"));
    assert!(!packet.matches_group(""));
}

#[test]
fn from_json_rejects_empty_group_or_device() {
    let empty_group = r#"{
        "group_id": "",
        "device_id": "device-a",
        "device_name": "Device A",
        "platform": "macos",
        "public_key": "public-key",
        "app_version": "1.0.0",
        "capabilities": ["text"]
    }"#;
    let empty_device = r#"{
        "group_id": "group-a",
        "device_id": "",
        "device_name": "Device A",
        "platform": "macos",
        "public_key": "public-key",
        "app_version": "1.0.0",
        "capabilities": ["text"]
    }"#;

    assert!(matches!(
        DiscoveryPacket::from_json(empty_group),
        Err(DiscoveryPacketError::InvalidField("group_id"))
    ));
    assert!(matches!(
        DiscoveryPacket::from_json(empty_device),
        Err(DiscoveryPacketError::InvalidField("device_id"))
    ));
}

#[test]
fn malformed_json_returns_json_error() {
    assert!(matches!(
        DiscoveryPacket::from_json("{"),
        Err(DiscoveryPacketError::Json(_))
    ));
}

#[test]
fn unknown_fields_are_ignored_for_forward_compatibility() {
    let json = r#"{
        "group_id": "group-a",
        "device_id": "device-a",
        "device_name": "Device A",
        "platform": "macos",
        "public_key": "public-key",
        "app_version": "1.0.0",
        "capabilities": ["text"],
        "future_field": "future-value"
    }"#;

    let packet = DiscoveryPacket::from_json(json).unwrap();

    assert_eq!(packet.group_id, "group-a");
    assert_eq!(packet.device_id, "device-a");
    assert_eq!(packet.capabilities, vec![PeerCapability::Text]);
}

#[test]
fn default_udp_config_uses_stable_discovery_endpoint() {
    let config = DiscoverySocketConfig::default();

    assert_eq!(DISCOVERY_PORT, 47_631);
    assert_eq!(
        DISCOVERY_BROADCAST,
        SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), DISCOVERY_PORT)
    );
    assert_eq!(config.bind_addr, Ipv4Addr::UNSPECIFIED);
    assert_eq!(config.bind_port, DISCOVERY_PORT);
    assert_eq!(config.broadcast_addr, DISCOVERY_BROADCAST);
}

#[tokio::test]
async fn discovery_udp_socket_sends_and_receives_datagrams() {
    let sender = DiscoveryUdpSocket::bind(DiscoverySocketConfig::ephemeral_for_test())
        .await
        .unwrap();
    let receiver = DiscoveryUdpSocket::bind(DiscoverySocketConfig::ephemeral_for_test())
        .await
        .unwrap();
    let payload = b"{\"kind\":\"hello\"}";

    sender
        .send_to(payload, receiver.local_addr())
        .await
        .unwrap();

    let DiscoveryDatagram {
        payload: received,
        source,
    } = timeout(Duration::from_secs(2), receiver.recv_datagram())
        .await
        .expect("receiver should receive datagram")
        .unwrap();

    assert_eq!(received, payload);
    assert_eq!(source, sender.local_addr());
}
