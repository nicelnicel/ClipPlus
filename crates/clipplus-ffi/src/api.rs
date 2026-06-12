use std::ffi::CStr;
use std::mem;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, TcpStream};
use std::os::raw::c_char;
use std::panic;
use std::path::{Path, PathBuf};
use std::ptr;

#[cfg(unix)]
use std::os::fd::FromRawFd;
#[cfg(windows)]
use std::os::windows::io::FromRawSocket;

use clipplus_crypto::key::SharedKeyMaterial;
use clipplus_diagnostics::status::RuntimeStatus;
use clipplus_discovery::udp::{
    BlockingDiscoveryUdpSocket, DiscoverySocketConfig, DISCOVERY_BROADCAST,
};
use clipplus_transport::file_transfer::{
    FileTransferArchive, FileTransferDownload, FileTransferServer, FileTransferTreeSummary,
};
use clipplus_transport::message::{NativeClipboardMessage, NativeFileTransferItem};

use crate::types::{free_c_string, string_to_c_ptr};

pub struct ClipPlusUdpSocketHandle {
    socket: BlockingDiscoveryUdpSocket,
}

pub struct ClipPlusFileServerHandle {
    server: FileTransferServer,
}

#[cfg(unix)]
unsafe fn tcp_stream_from_raw_socket_value(socket: usize) -> TcpStream {
    unsafe { TcpStream::from_raw_fd(socket as std::os::fd::RawFd) }
}

#[cfg(windows)]
unsafe fn tcp_stream_from_raw_socket_value(socket: usize) -> TcpStream {
    unsafe { TcpStream::from_raw_socket(socket as std::os::windows::io::RawSocket) }
}

#[no_mangle]
/// Returns the current runtime status as an owned JSON C string.
///
/// # Safety
///
/// The returned non-null pointer is read-only to callers, even though the ABI
/// uses `*mut c_char` so ownership can later be released. The pointer must be
/// passed back unchanged to [`clipplus_free_string`] exactly once. Do not modify
/// the buffer contents, insert an earlier NUL byte, change the string length,
/// or alter the terminating NUL before freeing it. A null pointer indicates
/// that status generation failed and must not be freed.
pub unsafe extern "C" fn clipplus_get_status_json() -> *mut c_char {
    panic::catch_unwind(|| {
        let status = RuntimeStatus::new_for_test();
        let json = serde_json::to_string(&status).expect("runtime status should serialize to JSON");

        string_to_c_ptr(json)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Derives the stable group identifier for a shared Key.
///
/// # Safety
///
/// `raw_key` must be null or point to a valid NUL-terminated C string. A null,
/// non-UTF-8, empty, or KDF-failing input returns null. The returned non-null
/// pointer follows the same ownership rules as [`clipplus_get_status_json`] and
/// must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_derive_group_id(raw_key: *const c_char) -> *mut c_char {
    panic::catch_unwind(|| {
        if raw_key.is_null() {
            return ptr::null_mut();
        }

        let raw_key = unsafe { CStr::from_ptr(raw_key) };
        let Ok(raw_key) = raw_key.to_str() else {
            return ptr::null_mut();
        };

        match SharedKeyMaterial::derive(raw_key) {
            Ok(material) => string_to_c_ptr(material.group_id),
            Err(_) => ptr::null_mut(),
        }
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Creates a hello message JSON string using the native shell wire format.
///
/// # Safety
///
/// All pointer arguments must be non-null valid NUL-terminated UTF-8 C strings.
/// Invalid, empty required fields or serialization failures return null. The returned
/// non-null pointer follows the same ownership rules as [`clipplus_get_status_json`]
/// and must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_create_hello_message_json(
    group_id: *const c_char,
    sender_device_id: *const c_char,
    sender_device_name: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(group_id) = ffi_string(group_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_id) = ffi_string(sender_device_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_name) = ffi_string(sender_device_name) else {
            return ptr::null_mut();
        };

        NativeClipboardMessage::hello(group_id, sender_device_id, sender_device_name)
            .and_then(|message| message.to_json())
            .map_or(ptr::null_mut(), string_to_c_ptr)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Creates a text clipboard message JSON string using the native shell wire format.
///
/// # Safety
///
/// All pointer arguments must be non-null valid NUL-terminated UTF-8 C strings.
/// Invalid, empty required fields or serialization failures return null. The returned
/// non-null pointer follows the same ownership rules as [`clipplus_get_status_json`]
/// and must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_create_text_message_json(
    group_id: *const c_char,
    sender_device_id: *const c_char,
    sender_device_name: *const c_char,
    text: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(group_id) = ffi_string(group_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_id) = ffi_string(sender_device_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_name) = ffi_string(sender_device_name) else {
            return ptr::null_mut();
        };
        let Some(text) = ffi_string(text) else {
            return ptr::null_mut();
        };

        match NativeClipboardMessage::text(group_id, sender_device_id, sender_device_name, text)
            .and_then(|message| message.to_json())
        {
            Ok(json) => string_to_c_ptr(json),
            Err(_) => ptr::null_mut(),
        }
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Creates an image clipboard message JSON string using the native shell wire format.
///
/// # Safety
///
/// String pointer arguments must be non-null valid NUL-terminated UTF-8 C strings.
/// `image_bytes` must be non-null and valid for `image_len` bytes. Invalid,
/// empty, oversized, or serialization-failing values return null. The returned
/// non-null pointer follows the same ownership rules as [`clipplus_get_status_json`]
/// and must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_create_image_message_json(
    group_id: *const c_char,
    sender_device_id: *const c_char,
    sender_device_name: *const c_char,
    image_bytes: *const u8,
    image_len: usize,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(group_id) = ffi_string(group_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_id) = ffi_string(sender_device_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_name) = ffi_string(sender_device_name) else {
            return ptr::null_mut();
        };
        if image_bytes.is_null() || image_len == 0 {
            return ptr::null_mut();
        }
        let image_bytes = unsafe { std::slice::from_raw_parts(image_bytes, image_len) };

        NativeClipboardMessage::image(group_id, sender_device_id, sender_device_name, image_bytes)
            .and_then(|message| message.to_json())
            .map_or(ptr::null_mut(), string_to_c_ptr)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Creates a file offer clipboard message JSON string using the native shell wire format.
///
/// # Safety
///
/// String pointer arguments must be non-null valid NUL-terminated UTF-8 C strings.
/// `files_json` must be a JSON array of native file transfer items. Invalid,
/// empty, unsafe path, zero-port, or serialization-failing values return null. The
/// returned non-null pointer follows the same ownership rules as
/// [`clipplus_get_status_json`] and must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_create_file_offer_message_json(
    group_id: *const c_char,
    sender_device_id: *const c_char,
    sender_device_name: *const c_char,
    transfer_id: *const c_char,
    files_json: *const c_char,
    archive_port: u16,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(group_id) = ffi_string(group_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_id) = ffi_string(sender_device_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_name) = ffi_string(sender_device_name) else {
            return ptr::null_mut();
        };
        let Some(transfer_id) = ffi_string(transfer_id) else {
            return ptr::null_mut();
        };
        let Some(files_json) = ffi_string(files_json) else {
            return ptr::null_mut();
        };
        let Ok(files) = serde_json::from_str::<Vec<NativeFileTransferItem>>(&files_json) else {
            return ptr::null_mut();
        };

        NativeClipboardMessage::file_offer(
            group_id,
            sender_device_id,
            sender_device_name,
            transfer_id,
            files,
            archive_port,
        )
        .and_then(|message| message.to_json())
        .map_or(ptr::null_mut(), string_to_c_ptr)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Writes a zip archive for file-transfer payloads using Rust transport logic.
///
/// # Safety
///
/// `source_paths_json` must be a non-null valid NUL-terminated UTF-8 C string
/// containing a JSON array of local source path strings. `archive_path` must be
/// a non-null valid NUL-terminated UTF-8 C string. The function returns false
/// for invalid inputs or IO/zip failures and does not expose paths in errors.
pub unsafe extern "C" fn clipplus_write_file_archive_zip(
    source_paths_json: *const c_char,
    archive_path: *const c_char,
) -> bool {
    panic::catch_unwind(|| {
        let Some(source_paths_json) = ffi_string(source_paths_json) else {
            return false;
        };
        let Some(archive_path) = ffi_string(archive_path) else {
            return false;
        };
        let Ok(source_paths) = serde_json::from_str::<Vec<String>>(&source_paths_json) else {
            return false;
        };
        let source_paths = source_paths.into_iter().map(Into::into).collect::<Vec<_>>();

        FileTransferArchive::write_zip(&source_paths, Path::new(&archive_path)).is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
/// Writes a length-prefixed zip archive to an accepted TCP socket.
///
/// # Safety
///
/// `socket` must be a valid connected TCP socket handle for the current
/// platform. The socket remains owned by the caller; this function writes to it
/// but does not close it. `source_paths_json` must be a JSON array of source
/// path strings and `archive_path` must be a writable temporary zip path.
/// Returns the archive byte count, or `0` on invalid inputs/IO failures.
pub unsafe extern "C" fn clipplus_serve_file_archive_to_socket(
    socket: usize,
    source_paths_json: *const c_char,
    archive_path: *const c_char,
) -> u64 {
    panic::catch_unwind(|| {
        if socket == 0 {
            return 0;
        }
        let Some(source_paths_json) = ffi_string(source_paths_json) else {
            return 0;
        };
        let Some(archive_path) = ffi_string(archive_path) else {
            return 0;
        };
        let Ok(source_paths) = serde_json::from_str::<Vec<String>>(&source_paths_json) else {
            return 0;
        };
        let source_paths = source_paths.into_iter().map(Into::into).collect::<Vec<_>>();
        let archive_path = Path::new(&archive_path);
        let mut stream = unsafe { tcp_stream_from_raw_socket_value(socket) };
        let result = FileTransferArchive::write_length_prefixed_zip(
            &source_paths,
            archive_path,
            &mut stream,
        );
        mem::forget(stream);
        let _ = std::fs::remove_file(archive_path);

        result.map_or(0, |summary| summary.byte_count)
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Downloads a length-prefixed file-transfer archive from a peer and writes it to disk.
///
/// # Safety
///
/// `host`, `transfer_id`, and `destination_path` must be non-null valid
/// NUL-terminated UTF-8 strings. `port` must be non-zero. The function returns
/// false for invalid inputs, network errors, oversized archives, and IO failures.
pub unsafe extern "C" fn clipplus_download_file_archive(
    host: *const c_char,
    port: u16,
    transfer_id: *const c_char,
    destination_path: *const c_char,
) -> bool {
    panic::catch_unwind(|| {
        let Some(host) = ffi_string(host) else {
            return false;
        };
        let Some(transfer_id) = ffi_string(transfer_id) else {
            return false;
        };
        let Some(destination_path) = ffi_string(destination_path) else {
            return false;
        };

        FileTransferDownload::download_to_path(
            &host,
            port,
            &transfer_id,
            Path::new(&destination_path),
        )
        .is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
/// Downloads a direct file-transfer tree from a peer and writes it to a directory.
///
/// # Safety
///
/// `host`, `transfer_id`, and `destination_dir` must be non-null valid
/// NUL-terminated UTF-8 strings. `port` must be non-zero. The returned non-null
/// pointer follows the same ownership rules as [`clipplus_get_status_json`] and
/// must be released with [`clipplus_free_string`]. Null indicates invalid input,
/// network errors, oversized payloads, unsafe paths, or IO failures.
pub unsafe extern "C" fn clipplus_download_file_tree(
    host: *const c_char,
    port: u16,
    transfer_id: *const c_char,
    destination_dir: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(host) = ffi_string(host) else {
            return ptr::null_mut();
        };
        let Some(transfer_id) = ffi_string(transfer_id) else {
            return ptr::null_mut();
        };
        let Some(destination_dir) = ffi_string(destination_dir) else {
            return ptr::null_mut();
        };

        FileTransferDownload::download_tree_to_directory(
            &host,
            port,
            &transfer_id,
            Path::new(&destination_dir),
        )
        .ok()
        .map(|summary| file_transfer_tree_summary_to_json(&summary))
        .map_or(ptr::null_mut(), string_to_c_ptr)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Binds a Rust file-transfer TCP server for native shells.
///
/// # Safety
///
/// Returns an opaque non-null handle on success. The handle must be passed back
/// to [`clipplus_file_server_free`] exactly once. `bind_port` may be `0` for an
/// ephemeral test port. Do not free the handle while another thread is using it.
pub unsafe extern "C" fn clipplus_file_server_bind(
    bind_port: u16,
) -> *mut ClipPlusFileServerHandle {
    panic::catch_unwind(|| {
        let Ok(server) = FileTransferServer::bind(bind_port) else {
            return ptr::null_mut();
        };

        Box::into_raw(Box::new(ClipPlusFileServerHandle { server }))
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Releases a Rust file-transfer TCP server handle.
///
/// # Safety
///
/// `handle` must be null or a pointer previously returned by
/// [`clipplus_file_server_bind`] that has not already been freed. Callers must
/// not free the handle concurrently with `register_transfer` or `serve_next`.
pub unsafe extern "C" fn clipplus_file_server_free(handle: *mut ClipPlusFileServerHandle) {
    if handle.is_null() {
        return;
    }

    let _ = panic::catch_unwind(|| unsafe { drop(Box::from_raw(handle)) });
}

#[no_mangle]
/// Returns the local TCP port for a Rust file-transfer server handle.
///
/// # Safety
///
/// `handle` must be null or a valid pointer returned by
/// [`clipplus_file_server_bind`]. Invalid handles return `0`.
pub unsafe extern "C" fn clipplus_file_server_local_port(
    handle: *mut ClipPlusFileServerHandle,
) -> u16 {
    panic::catch_unwind(|| {
        if handle.is_null() {
            return 0;
        }

        let handle = unsafe { &*handle };
        handle.server.local_port().unwrap_or(0)
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Registers source paths for a file-transfer id on a Rust file server.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by [`clipplus_file_server_bind`].
/// `transfer_id` and `source_paths_json` must be non-null valid
/// NUL-terminated UTF-8 strings. `source_paths_json` must be a JSON array of
/// local source path strings. Invalid inputs return false.
pub unsafe extern "C" fn clipplus_file_server_register_transfer(
    handle: *mut ClipPlusFileServerHandle,
    transfer_id: *const c_char,
    source_paths_json: *const c_char,
) -> bool {
    panic::catch_unwind(|| {
        if handle.is_null() {
            return false;
        }
        let Some(transfer_id) = ffi_string(transfer_id) else {
            return false;
        };
        let Some(source_paths_json) = ffi_string(source_paths_json) else {
            return false;
        };
        let Ok(source_paths) = serde_json::from_str::<Vec<String>>(&source_paths_json) else {
            return false;
        };
        let source_paths = source_paths
            .into_iter()
            .map(PathBuf::from)
            .collect::<Vec<_>>();

        let handle = unsafe { &*handle };
        handle
            .server
            .register_transfer(&transfer_id, source_paths)
            .is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
/// Serves one registered file-transfer archive to the next TCP client.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by [`clipplus_file_server_bind`].
/// `temp_dir` must be a non-null valid NUL-terminated UTF-8 string naming an
/// existing directory used for the temporary zip. This call blocks until one
/// client connects or the listener errors. It returns the archive byte count, or
/// `0` on invalid inputs, unknown transfer id, or IO/zip failure.
pub unsafe extern "C" fn clipplus_file_server_serve_next(
    handle: *mut ClipPlusFileServerHandle,
    temp_dir: *const c_char,
) -> u64 {
    panic::catch_unwind(|| {
        if handle.is_null() {
            return 0;
        }
        let Some(temp_dir) = ffi_string(temp_dir) else {
            return 0;
        };

        let handle = unsafe { &*handle };
        handle
            .server
            .serve_next(Path::new(&temp_dir))
            .map_or(0, |summary| summary.byte_count)
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Serves one registered direct file-transfer tree to the next TCP client.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by [`clipplus_file_server_bind`].
/// This call blocks until one client connects or the listener errors. It returns
/// the streamed file byte count, or `0` on null handle, unknown transfer id,
/// invalid paths, or IO failure.
pub unsafe extern "C" fn clipplus_file_server_serve_next_tree(
    handle: *mut ClipPlusFileServerHandle,
) -> u64 {
    panic::catch_unwind(|| {
        if handle.is_null() {
            return 0;
        }

        let handle = unsafe { &*handle };
        handle
            .server
            .serve_next_tree()
            .map_or(0, |summary| summary.byte_count)
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Binds a Rust UDP discovery socket for native shells.
///
/// # Safety
///
/// Returns an opaque non-null handle on success. The handle must be passed back to
/// [`clipplus_udp_socket_free`] exactly once. `bind_port` may be `0` for an
/// ephemeral test port.
pub unsafe extern "C" fn clipplus_udp_socket_bind(bind_port: u16) -> *mut ClipPlusUdpSocketHandle {
    panic::catch_unwind(|| {
        let config = DiscoverySocketConfig {
            bind_addr: Ipv4Addr::UNSPECIFIED,
            bind_port,
            broadcast_addr: DISCOVERY_BROADCAST,
        };
        let Ok(socket) = BlockingDiscoveryUdpSocket::bind(config) else {
            return ptr::null_mut();
        };

        Box::into_raw(Box::new(ClipPlusUdpSocketHandle { socket }))
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Releases a Rust UDP discovery socket handle.
///
/// # Safety
///
/// `handle` must be null or a pointer previously returned by
/// [`clipplus_udp_socket_bind`] that has not already been freed.
pub unsafe extern "C" fn clipplus_udp_socket_free(handle: *mut ClipPlusUdpSocketHandle) {
    if handle.is_null() {
        return;
    }

    let _ = panic::catch_unwind(|| unsafe { drop(Box::from_raw(handle)) });
}

#[no_mangle]
/// Returns the local UDP port for a Rust discovery socket handle.
///
/// # Safety
///
/// `handle` must be null or a valid pointer returned by
/// [`clipplus_udp_socket_bind`]. Invalid handles return `0`.
pub unsafe extern "C" fn clipplus_udp_socket_local_port(
    handle: *mut ClipPlusUdpSocketHandle,
) -> u16 {
    panic::catch_unwind(|| {
        if handle.is_null() {
            return 0;
        }

        let handle = unsafe { &*handle };
        handle.socket.local_addr().port()
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Sends a UDP datagram through a Rust discovery socket.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by [`clipplus_udp_socket_bind`].
/// `payload` must be valid for `payload_len` bytes. `target_host` must be a
/// valid NUL-terminated IPv4 string. Invalid input or IO failures return false.
pub unsafe extern "C" fn clipplus_udp_socket_send_to(
    handle: *mut ClipPlusUdpSocketHandle,
    payload: *const u8,
    payload_len: usize,
    target_host: *const c_char,
    target_port: u16,
) -> bool {
    panic::catch_unwind(|| {
        if handle.is_null() || payload.is_null() || payload_len == 0 || target_port == 0 {
            return false;
        }
        let Some(target_host) = ffi_string(target_host) else {
            return false;
        };
        let Ok(target_ip) = target_host.parse::<Ipv4Addr>() else {
            return false;
        };

        let handle = unsafe { &*handle };
        let payload = unsafe { std::slice::from_raw_parts(payload, payload_len) };
        handle
            .socket
            .send_to(
                payload,
                SocketAddr::V4(SocketAddrV4::new(target_ip, target_port)),
            )
            .is_ok()
    })
    .unwrap_or(false)
}

#[no_mangle]
/// Receives one UDP datagram through a Rust discovery socket.
///
/// # Safety
///
/// `handle` must be a valid pointer returned by [`clipplus_udp_socket_bind`].
/// `buffer` must be valid for `buffer_len` bytes. `source_host_buffer` must be
/// valid for `source_host_len` bytes and receives a NUL-terminated IPv4 string.
/// `source_port` must be writable. The function returns the payload byte count,
/// or `0` on timeout, invalid input, truncation, or IO failure.
pub unsafe extern "C" fn clipplus_udp_socket_recv(
    handle: *mut ClipPlusUdpSocketHandle,
    buffer: *mut u8,
    buffer_len: usize,
    source_host_buffer: *mut c_char,
    source_host_len: usize,
    source_port: *mut u16,
) -> usize {
    panic::catch_unwind(|| {
        if handle.is_null()
            || buffer.is_null()
            || buffer_len == 0
            || source_host_buffer.is_null()
            || source_host_len == 0
            || source_port.is_null()
        {
            return 0;
        }

        let handle = unsafe { &*handle };
        let Ok(Some(datagram)) = handle.socket.recv_datagram() else {
            return 0;
        };
        if datagram.payload.len() > buffer_len {
            return 0;
        }

        let SocketAddr::V4(source_addr) = datagram.source else {
            return 0;
        };
        let source_host = source_addr.ip().to_string();
        if source_host.len() + 1 > source_host_len {
            return 0;
        }

        unsafe {
            ptr::copy_nonoverlapping(datagram.payload.as_ptr(), buffer, datagram.payload.len());
            ptr::copy_nonoverlapping(
                source_host.as_ptr().cast::<c_char>(),
                source_host_buffer,
                source_host.len(),
            );
            *source_host_buffer.add(source_host.len()) = 0;
            *source_port = source_addr.port();
        }

        datagram.payload.len()
    })
    .unwrap_or(0)
}

#[no_mangle]
/// Creates a trust message JSON string using the native shell wire format.
///
/// # Safety
///
/// All pointer arguments must be non-null valid NUL-terminated UTF-8 C strings.
/// Invalid, empty required fields or serialization failures return null. The returned
/// non-null pointer follows the same ownership rules as [`clipplus_get_status_json`]
/// and must be released with [`clipplus_free_string`].
pub unsafe extern "C" fn clipplus_create_trust_message_json(
    group_id: *const c_char,
    sender_device_id: *const c_char,
    sender_device_name: *const c_char,
    approved_device_id: *const c_char,
) -> *mut c_char {
    panic::catch_unwind(|| {
        let Some(group_id) = ffi_string(group_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_id) = ffi_string(sender_device_id) else {
            return ptr::null_mut();
        };
        let Some(sender_device_name) = ffi_string(sender_device_name) else {
            return ptr::null_mut();
        };
        let Some(approved_device_id) = ffi_string(approved_device_id) else {
            return ptr::null_mut();
        };

        NativeClipboardMessage::trust(
            group_id,
            sender_device_id,
            sender_device_name,
            approved_device_id,
        )
        .and_then(|message| message.to_json())
        .map_or(ptr::null_mut(), string_to_c_ptr)
    })
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
/// Releases a string allocated by this FFI crate.
///
/// # Safety
///
/// `ptr` must be null or a pointer returned by this crate that has not already
/// been freed. Non-null pointers must be passed back unchanged: callers must
/// not modify the buffer contents, insert an earlier NUL byte, change the
/// string length, or alter the terminating NUL after receiving the pointer.
/// Passing any other pointer, a previously freed pointer, or a modified pointer
/// is undefined behavior.
pub unsafe extern "C" fn clipplus_free_string(ptr: *mut c_char) {
    let _ = panic::catch_unwind(|| unsafe {
        free_c_string(ptr);
    });
}

fn ffi_string(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }

    let value = unsafe { CStr::from_ptr(ptr) }.to_str().ok()?;
    Some(value.to_string())
}

#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct FileTransferTreeSummaryJson {
    file_count: usize,
    byte_count: u64,
    top_level_paths: Vec<String>,
}

fn file_transfer_tree_summary_to_json(summary: &FileTransferTreeSummary) -> String {
    let top_level_paths = summary
        .top_level_paths
        .iter()
        .map(|path| path.to_string_lossy().to_string())
        .collect();

    serde_json::to_string(&FileTransferTreeSummaryJson {
        file_count: summary.file_count,
        byte_count: summary.byte_count,
        top_level_paths,
    })
    .expect("file transfer tree summary should serialize to JSON")
}
