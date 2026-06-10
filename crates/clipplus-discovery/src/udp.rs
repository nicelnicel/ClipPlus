use std::io::ErrorKind;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket as StdUdpSocket};
use std::time::Duration;

use thiserror::Error;
use tokio::net::UdpSocket;

pub const DISCOVERY_PORT: u16 = 47_631;
pub const DISCOVERY_BROADCAST: SocketAddrV4 =
    SocketAddrV4::new(Ipv4Addr::new(255, 255, 255, 255), DISCOVERY_PORT);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DiscoverySocketConfig {
    pub bind_addr: Ipv4Addr,
    pub bind_port: u16,
    pub broadcast_addr: SocketAddrV4,
}

impl DiscoverySocketConfig {
    pub fn ephemeral_for_test() -> Self {
        Self {
            bind_addr: Ipv4Addr::LOCALHOST,
            bind_port: 0,
            broadcast_addr: SocketAddrV4::new(Ipv4Addr::LOCALHOST, 0),
        }
    }
}

impl Default for DiscoverySocketConfig {
    fn default() -> Self {
        Self {
            bind_addr: Ipv4Addr::UNSPECIFIED,
            bind_port: DISCOVERY_PORT,
            broadcast_addr: DISCOVERY_BROADCAST,
        }
    }
}

#[derive(Debug, Error)]
pub enum DiscoveryUdpError {
    #[error("udp socket io error: {0}")]
    Io(#[from] std::io::Error),
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DiscoveryDatagram {
    pub payload: Vec<u8>,
    pub source: SocketAddr,
}

pub struct DiscoveryUdpSocket {
    socket: UdpSocket,
    broadcast_addr: SocketAddrV4,
}

impl DiscoveryUdpSocket {
    pub async fn bind(config: DiscoverySocketConfig) -> Result<Self, DiscoveryUdpError> {
        let socket = UdpSocket::bind(SocketAddrV4::new(config.bind_addr, config.bind_port)).await?;
        socket.set_broadcast(true)?;

        Ok(Self {
            socket,
            broadcast_addr: config.broadcast_addr,
        })
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.socket
            .local_addr()
            .expect("bound UDP socket should expose a local address")
    }

    pub async fn send_to(
        &self,
        payload: &[u8],
        target: SocketAddr,
    ) -> Result<usize, DiscoveryUdpError> {
        Ok(self.socket.send_to(payload, target).await?)
    }

    pub async fn broadcast(&self, payload: &[u8]) -> Result<usize, DiscoveryUdpError> {
        Ok(self.socket.send_to(payload, self.broadcast_addr).await?)
    }

    pub async fn recv_datagram(&self) -> Result<DiscoveryDatagram, DiscoveryUdpError> {
        let mut buffer = vec![0; 65_535];
        let (byte_count, source) = self.socket.recv_from(&mut buffer).await?;
        buffer.truncate(byte_count);

        Ok(DiscoveryDatagram {
            payload: buffer,
            source,
        })
    }
}

pub struct BlockingDiscoveryUdpSocket {
    socket: StdUdpSocket,
    broadcast_addr: SocketAddrV4,
}

impl BlockingDiscoveryUdpSocket {
    pub fn bind(config: DiscoverySocketConfig) -> Result<Self, DiscoveryUdpError> {
        let socket = StdUdpSocket::bind(SocketAddrV4::new(config.bind_addr, config.bind_port))?;
        socket.set_broadcast(true)?;
        socket.set_read_timeout(Some(Duration::from_millis(250)))?;

        Ok(Self {
            socket,
            broadcast_addr: config.broadcast_addr,
        })
    }

    pub fn local_addr(&self) -> SocketAddr {
        self.socket
            .local_addr()
            .expect("bound UDP socket should expose a local address")
    }

    pub fn send_to(&self, payload: &[u8], target: SocketAddr) -> Result<usize, DiscoveryUdpError> {
        Ok(self.socket.send_to(payload, target)?)
    }

    pub fn broadcast(&self, payload: &[u8]) -> Result<usize, DiscoveryUdpError> {
        Ok(self.socket.send_to(payload, self.broadcast_addr)?)
    }

    pub fn recv_datagram(&self) -> Result<Option<DiscoveryDatagram>, DiscoveryUdpError> {
        let mut buffer = vec![0; 65_535];
        match self.socket.recv_from(&mut buffer) {
            Ok((byte_count, source)) => {
                buffer.truncate(byte_count);
                Ok(Some(DiscoveryDatagram {
                    payload: buffer,
                    source,
                }))
            }
            Err(error) if matches!(error.kind(), ErrorKind::WouldBlock | ErrorKind::TimedOut) => {
                Ok(None)
            }
            Err(error) => Err(error.into()),
        }
    }
}
