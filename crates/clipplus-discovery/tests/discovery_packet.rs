use clipplus_discovery::packet::{DiscoveryPacket, PeerCapability};
use clipplus_discovery::udp::{DiscoverySocketConfig, DISCOVERY_BROADCAST, DISCOVERY_PORT};
use std::net::{Ipv4Addr, SocketAddrV4};

#[test]
fn discovery_packet_roundtrips_json() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    let json = packet.to_json().unwrap();
    let decoded = DiscoveryPacket::from_json(&json).unwrap();

    assert_eq!(decoded.group_id, "group-a");
    assert_eq!(decoded.device_id, "device-a");
    assert!(decoded.capabilities.contains(&PeerCapability::Text));
    assert!(!json.contains("raw-secret-key"));
}

#[test]
fn group_mismatch_is_rejected() {
    let packet = DiscoveryPacket::new_for_test("group-a", "device-a");

    assert!(!packet.matches_group("group-b"));
    assert!(packet.matches_group("group-a"));
}

#[test]
fn default_udp_config_uses_stable_discovery_endpoint() {
    let config = DiscoverySocketConfig::default();

    assert_eq!(DISCOVERY_PORT, 47_631);
    assert_eq!(
        DISCOVERY_BROADCAST,
        SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), DISCOVERY_PORT)
    );
    assert_eq!(config.bind_port, DISCOVERY_PORT);
    assert_eq!(config.broadcast_addr, DISCOVERY_BROADCAST);
}
