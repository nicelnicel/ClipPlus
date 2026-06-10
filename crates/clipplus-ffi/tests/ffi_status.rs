use std::ffi::{CStr, CString};
use std::io::{BufRead, Read, Write};
use std::net::TcpListener;
use std::path::{Path, PathBuf};
use std::ptr;
use std::thread;

use clipplus_ffi::api::{
    clipplus_create_file_offer_message_json, clipplus_create_hello_message_json,
    clipplus_create_image_message_json, clipplus_create_text_message_json,
    clipplus_create_trust_message_json, clipplus_derive_group_id, clipplus_download_file_archive,
    clipplus_free_string, clipplus_get_status_json, clipplus_udp_socket_bind,
    clipplus_udp_socket_free, clipplus_udp_socket_local_port, clipplus_udp_socket_recv,
    clipplus_udp_socket_send_to, clipplus_write_file_archive_zip,
};
use clipplus_ffi::{
    clipplus_create_file_offer_message_json as reexported_create_file_offer_message_json,
    clipplus_create_hello_message_json as reexported_create_hello_message_json,
    clipplus_create_image_message_json as reexported_create_image_message_json,
    clipplus_create_text_message_json as reexported_create_text_message_json,
    clipplus_create_trust_message_json as reexported_create_trust_message_json,
    clipplus_derive_group_id as reexported_derive_group_id,
    clipplus_download_file_archive as reexported_download_file_archive,
    clipplus_free_string as reexported_free_string,
    clipplus_get_status_json as reexported_get_status_json,
    clipplus_udp_socket_bind as reexported_udp_socket_bind,
    clipplus_write_file_archive_zip as reexported_write_file_archive_zip,
};
use serde_json::Value;

unsafe fn take_status_json(ptr: *mut std::ffi::c_char) -> String {
    assert!(!ptr.is_null());

    let json = unsafe { CStr::from_ptr(ptr).to_string_lossy().to_string() };
    unsafe { reexported_free_string(ptr) };
    json
}

unsafe fn take_ffi_string(ptr: *mut std::ffi::c_char) -> String {
    assert!(!ptr.is_null());

    let value = unsafe { CStr::from_ptr(ptr).to_string_lossy().to_string() };
    unsafe { reexported_free_string(ptr) };
    value
}

#[test]
fn ffi_returns_status_json_and_frees_string() {
    let ptr = unsafe { clipplus_get_status_json() };
    let json = unsafe { take_status_json(ptr) };

    assert!(json.contains("core_version"));
}

#[test]
fn ffi_free_string_ignores_null_pointer() {
    unsafe { clipplus_free_string(ptr::null_mut()) };
}

#[test]
fn ffi_reexported_free_string_ignores_null_pointer() {
    unsafe { reexported_free_string(ptr::null_mut()) };
}

#[test]
fn ffi_status_json_is_parseable_safe_status() {
    let ptr = unsafe { clipplus_get_status_json() };
    let json = unsafe { take_status_json(ptr) };
    let value: Value = serde_json::from_str(&json).expect("status json should parse");

    assert!(value.get("core_version").is_some());
    assert!(value.get("last_clipboard_event_summary").is_some());
    assert!(!json.contains("SECRET_CLIPBOARD_CANARY"));
}

#[test]
fn ffi_status_json_is_available_from_lib_reexport() {
    let ptr = unsafe { reexported_get_status_json() };
    let json = unsafe { take_status_json(ptr) };

    assert!(json.contains("core_version"));
}

#[test]
fn ffi_derives_shared_key_group_id() {
    let raw_key = CString::new("friend-lan-key").unwrap();
    let ptr = unsafe { clipplus_derive_group_id(raw_key.as_ptr()) };
    let group_id = unsafe { take_ffi_string(ptr) };

    assert_eq!(group_id, "6OPi4Ya2nYZkISrKO0RGzQ");
    assert_ne!(group_id, "friend-lan-key");
}

#[test]
fn ffi_derives_group_id_from_reexport() {
    let raw_key = CString::new(" friend-lan-key ").unwrap();
    let ptr = unsafe { reexported_derive_group_id(raw_key.as_ptr()) };
    let group_id = unsafe { take_ffi_string(ptr) };

    assert_eq!(group_id, "6OPi4Ya2nYZkISrKO0RGzQ");
}

#[test]
fn ffi_derive_group_id_rejects_null_and_empty_keys() {
    let empty_key = CString::new("   ").unwrap();

    assert!(unsafe { clipplus_derive_group_id(ptr::null()) }.is_null());
    assert!(unsafe { clipplus_derive_group_id(empty_key.as_ptr()) }.is_null());
}

#[test]
fn ffi_creates_text_message_json_for_native_shells() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let text = CString::new("hello from rust ffi").unwrap();

    let ptr = unsafe {
        clipplus_create_text_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            text.as_ptr(),
        )
    };
    let json = unsafe { take_ffi_string(ptr) };
    let value: Value = serde_json::from_str(&json).expect("message json should parse");

    assert_eq!(value["kind"], "text");
    assert_eq!(value["protocolVersion"], 1);
    assert_eq!(value["groupId"], "group-1");
    assert_eq!(value["senderDeviceId"], "mac-device");
    assert_eq!(value["senderDeviceName"], "Mac");
    assert_eq!(value["text"], "hello from rust ffi");
    assert!(value["eventId"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
    assert!(value["createdAt"]
        .as_str()
        .is_some_and(|value| !value.is_empty()));
}

#[test]
fn ffi_create_text_message_json_rejects_missing_required_values() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let text = CString::new("hello").unwrap();

    assert!(unsafe {
        reexported_create_text_message_json(
            ptr::null(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            text.as_ptr(),
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_text_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            ptr::null(),
        )
    }
    .is_null());
}

#[test]
fn ffi_creates_hello_message_json_for_native_shells() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();

    let ptr = unsafe {
        clipplus_create_hello_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
        )
    };
    let json = unsafe { take_ffi_string(ptr) };
    let value: Value = serde_json::from_str(&json).expect("message json should parse");

    assert_eq!(value["kind"], "hello");
    assert_eq!(value["protocolVersion"], 1);
    assert_eq!(value["groupId"], "group-1");
    assert_eq!(value["senderDeviceId"], "mac-device");
    assert_eq!(value["senderDeviceName"], "Mac");
    assert!(value.get("text").is_none());
}

#[test]
fn ffi_creates_trust_message_json_for_native_shells() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let approved_device_id = CString::new("windows-device").unwrap();

    let ptr = unsafe {
        clipplus_create_trust_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            approved_device_id.as_ptr(),
        )
    };
    let json = unsafe { take_ffi_string(ptr) };
    let value: Value = serde_json::from_str(&json).expect("message json should parse");

    assert_eq!(value["kind"], "trust");
    assert_eq!(value["protocolVersion"], 1);
    assert_eq!(value["groupId"], "group-1");
    assert_eq!(value["senderDeviceId"], "mac-device");
    assert_eq!(value["approvedDeviceId"], "windows-device");
}

#[test]
fn ffi_create_hello_and_trust_message_json_reject_missing_required_values() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();

    assert!(unsafe {
        reexported_create_hello_message_json(
            ptr::null(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_trust_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            ptr::null(),
        )
    }
    .is_null());
}

#[test]
fn ffi_creates_image_message_json_for_native_shells() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let png_bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

    let ptr = unsafe {
        clipplus_create_image_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            png_bytes.as_ptr(),
            png_bytes.len(),
        )
    };
    let json = unsafe { take_ffi_string(ptr) };
    let value: Value = serde_json::from_str(&json).expect("message json should parse");

    assert_eq!(value["kind"], "image");
    assert_eq!(value["protocolVersion"], 1);
    assert_eq!(value["groupId"], "group-1");
    assert_eq!(value["senderDeviceId"], "mac-device");
    assert_eq!(value["imageBase64"], "iVBORw0KGgo=");
    assert_eq!(value["imageByteSize"], 8);
    assert_eq!(
        value["imageContentHash"],
        "4c4b6a3be1314ab86138bef4314dde022e600960d8689a2c8f8631802d20dab6"
    );
}

#[test]
fn ffi_create_image_message_json_rejects_null_empty_and_oversized_values() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let png_bytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    let oversized = vec![0xFF; 32 * 1024 + 1];

    assert!(unsafe {
        reexported_create_image_message_json(
            ptr::null(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            png_bytes.as_ptr(),
            png_bytes.len(),
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_image_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            ptr::null(),
            png_bytes.len(),
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_image_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            png_bytes.as_ptr(),
            0,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_image_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            oversized.as_ptr(),
            oversized.len(),
        )
    }
    .is_null());
}

#[test]
fn ffi_creates_file_offer_message_json_for_native_shells() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let transfer_id = CString::new("transfer-1").unwrap();
    let files_json = CString::new(
        r#"[{"relativePath":"Reports/Q1.txt","byteSize":12,"isDirectory":false},{"relativePath":"Screenshots","byteSize":34,"isDirectory":true}]"#,
    )
    .unwrap();

    let ptr = unsafe {
        clipplus_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            files_json.as_ptr(),
            47_632,
        )
    };
    let json = unsafe { take_ffi_string(ptr) };
    let value: Value = serde_json::from_str(&json).expect("message json should parse");

    assert_eq!(value["kind"], "fileOffer");
    assert_eq!(value["protocolVersion"], 1);
    assert_eq!(value["groupId"], "group-1");
    assert_eq!(value["senderDeviceId"], "mac-device");
    assert_eq!(value["transferId"], "transfer-1");
    assert_eq!(value["archivePort"], 47_632);
    assert_eq!(value["files"][0]["relativePath"], "Reports/Q1.txt");
    assert_eq!(value["files"][0]["byteSize"], 12);
    assert_eq!(value["files"][0]["isDirectory"], false);
    assert_eq!(value["files"][1]["relativePath"], "Screenshots");
    assert!(!json.contains("/Users/"));
    assert!(!json.contains("C:\\"));
}

#[test]
fn ffi_create_file_offer_message_json_rejects_invalid_values() {
    let group_id = CString::new("group-1").unwrap();
    let sender_device_id = CString::new("mac-device").unwrap();
    let sender_device_name = CString::new("Mac").unwrap();
    let transfer_id = CString::new("transfer-1").unwrap();
    let blank_transfer_id = CString::new(" ").unwrap();
    let valid_files =
        CString::new(r#"[{"relativePath":"Reports/Q1.txt","byteSize":12,"isDirectory":false}]"#)
            .unwrap();
    let empty_files = CString::new("[]").unwrap();
    let invalid_files = CString::new("not-json").unwrap();
    let absolute_file = CString::new(
        r#"[{"relativePath":"/Users/cc/private.txt","byteSize":12,"isDirectory":false}]"#,
    )
    .unwrap();

    assert!(unsafe {
        reexported_create_file_offer_message_json(
            ptr::null(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            valid_files.as_ptr(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            blank_transfer_id.as_ptr(),
            valid_files.as_ptr(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            ptr::null(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            empty_files.as_ptr(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            invalid_files.as_ptr(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            absolute_file.as_ptr(),
            47_632,
        )
    }
    .is_null());
    assert!(unsafe {
        reexported_create_file_offer_message_json(
            group_id.as_ptr(),
            sender_device_id.as_ptr(),
            sender_device_name.as_ptr(),
            transfer_id.as_ptr(),
            valid_files.as_ptr(),
            0,
        )
    }
    .is_null());
}

#[test]
fn ffi_writes_file_archive_zip_for_native_shells() {
    let temporary_directory = unique_temp_dir();
    let source_directory = temporary_directory.join("source");
    let nested_directory = source_directory.join("Nested");
    std::fs::create_dir_all(&nested_directory).unwrap();
    std::fs::write(source_directory.join("a.txt"), "alpha").unwrap();
    std::fs::write(nested_directory.join("b.txt"), "beta").unwrap();
    let archive_path = temporary_directory.join("files.zip");
    let source_paths_json = CString::new(format!(
        r#"["{}","{}"]"#,
        json_escape_path(&source_directory.join("a.txt")),
        json_escape_path(&nested_directory)
    ))
    .unwrap();
    let archive_path = CString::new(archive_path.to_string_lossy().to_string()).unwrap();

    let written = unsafe {
        clipplus_write_file_archive_zip(source_paths_json.as_ptr(), archive_path.as_ptr())
    };

    assert!(written);
    assert_eq!(
        read_zip_entries(Path::new(archive_path.to_str().unwrap())),
        vec![
            ("Nested/b.txt".to_string(), "beta".to_string()),
            ("a.txt".to_string(), "alpha".to_string()),
        ]
    );
}

#[test]
fn ffi_write_file_archive_zip_rejects_invalid_values() {
    let temporary_directory = unique_temp_dir();
    let archive_path = CString::new(
        temporary_directory
            .join("files.zip")
            .to_string_lossy()
            .to_string(),
    )
    .unwrap();
    let empty_sources = CString::new("[]").unwrap();
    let invalid_sources = CString::new("not-json").unwrap();

    assert!(!unsafe { reexported_write_file_archive_zip(ptr::null(), archive_path.as_ptr()) });
    assert!(!unsafe {
        reexported_write_file_archive_zip(empty_sources.as_ptr(), archive_path.as_ptr())
    });
    assert!(!unsafe {
        reexported_write_file_archive_zip(invalid_sources.as_ptr(), archive_path.as_ptr())
    });
    assert!(!unsafe { reexported_write_file_archive_zip(empty_sources.as_ptr(), ptr::null()) });
}

#[test]
fn ffi_downloads_file_archive_for_native_shells() {
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

        let payload = b"archive from ffi server";
        stream
            .write_all(&(payload.len() as u64).to_be_bytes())
            .unwrap();
        stream.write_all(payload).unwrap();
    });
    let host = CString::new("127.0.0.1").unwrap();
    let transfer_id = CString::new("transfer-a").unwrap();
    let destination_path = CString::new(destination_path.to_string_lossy().to_string()).unwrap();

    let downloaded = unsafe {
        clipplus_download_file_archive(
            host.as_ptr(),
            port,
            transfer_id.as_ptr(),
            destination_path.as_ptr(),
        )
    };
    server.join().unwrap();

    assert!(downloaded);
    assert_eq!(
        std::fs::read(Path::new(destination_path.to_str().unwrap())).unwrap(),
        b"archive from ffi server"
    );
}

#[test]
fn ffi_download_file_archive_rejects_invalid_values() {
    let temporary_directory = unique_temp_dir();
    let destination_path = CString::new(
        temporary_directory
            .join("received.zip")
            .to_string_lossy()
            .to_string(),
    )
    .unwrap();
    let host = CString::new("127.0.0.1").unwrap();
    let empty = CString::new(" ").unwrap();
    let transfer_id = CString::new("transfer-a").unwrap();

    assert!(!unsafe {
        reexported_download_file_archive(
            ptr::null(),
            47_632,
            transfer_id.as_ptr(),
            destination_path.as_ptr(),
        )
    });
    assert!(!unsafe {
        reexported_download_file_archive(
            empty.as_ptr(),
            47_632,
            transfer_id.as_ptr(),
            destination_path.as_ptr(),
        )
    });
    assert!(!unsafe {
        reexported_download_file_archive(
            host.as_ptr(),
            0,
            transfer_id.as_ptr(),
            destination_path.as_ptr(),
        )
    });
    assert!(!unsafe {
        reexported_download_file_archive(
            host.as_ptr(),
            47_632,
            ptr::null(),
            destination_path.as_ptr(),
        )
    });
}

#[test]
fn ffi_udp_socket_sends_and_receives_datagrams_for_native_shells() {
    let receiver = unsafe { clipplus_udp_socket_bind(0) };
    let sender = unsafe { clipplus_udp_socket_bind(0) };
    assert!(!receiver.is_null());
    assert!(!sender.is_null());

    let receiver_port = unsafe { clipplus_udp_socket_local_port(receiver) };
    assert_ne!(receiver_port, 0);
    let target_host = CString::new("127.0.0.1").unwrap();
    let payload = b"hello from udp ffi";
    assert!(unsafe {
        clipplus_udp_socket_send_to(
            sender,
            payload.as_ptr(),
            payload.len(),
            target_host.as_ptr(),
            receiver_port,
        )
    });

    let mut buffer = [0_u8; 128];
    let mut source_host = [0_i8; 64];
    let mut source_port = 0_u16;
    let byte_count = unsafe {
        clipplus_udp_socket_recv(
            receiver,
            buffer.as_mut_ptr(),
            buffer.len(),
            source_host.as_mut_ptr(),
            source_host.len(),
            &mut source_port,
        )
    };

    assert_eq!(&buffer[..byte_count], payload);
    let source_host = unsafe { CStr::from_ptr(source_host.as_ptr()) }
        .to_str()
        .unwrap();
    assert_eq!(source_host, "127.0.0.1");
    assert_ne!(source_port, 0);

    unsafe {
        clipplus_udp_socket_free(sender);
        clipplus_udp_socket_free(receiver);
    }
}

#[test]
fn ffi_udp_socket_rejects_invalid_values() {
    let socket = unsafe { reexported_udp_socket_bind(0) };
    assert!(!socket.is_null());
    let target_host = CString::new("127.0.0.1").unwrap();
    let payload = b"hello";
    assert!(!unsafe {
        clipplus_udp_socket_send_to(
            ptr::null_mut(),
            payload.as_ptr(),
            payload.len(),
            target_host.as_ptr(),
            47_631,
        )
    });
    assert!(!unsafe {
        clipplus_udp_socket_send_to(
            socket,
            ptr::null(),
            payload.len(),
            target_host.as_ptr(),
            47_631,
        )
    });
    assert_eq!(
        unsafe {
            clipplus_udp_socket_recv(
                ptr::null_mut(),
                ptr::null_mut(),
                0,
                ptr::null_mut(),
                0,
                ptr::null_mut(),
            )
        },
        0
    );
    unsafe { clipplus_udp_socket_free(socket) };
}

fn unique_temp_dir() -> PathBuf {
    let path = std::env::temp_dir().join(format!("clipplus-ffi-{}", std::process::id()));
    let path = path.join(format!(
        "{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&path).unwrap();
    path
}

fn json_escape_path(path: &Path) -> String {
    path.to_string_lossy()
        .replace('\\', "\\\\")
        .replace('"', "\\\"")
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
