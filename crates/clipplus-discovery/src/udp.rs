use std::net::{Ipv4Addr, SocketAddrV4};

pub const DISCOVERY_PORT: u16 = 47_631;
pub const DISCOVERY_BROADCAST: SocketAddrV4 =
    SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), DISCOVERY_PORT);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiscoverySocketConfig {
    pub bind_port: u16,
    pub broadcast_addr: SocketAddrV4,
}

impl Default for DiscoverySocketConfig {
    fn default() -> Self {
        Self {
            bind_port: DISCOVERY_PORT,
            broadcast_addr: DISCOVERY_BROADCAST,
        }
    }
}
