use std::ffi::{CStr, CString};
use std::ptr;

use clipplus_ffi::api::{
    clipplus_create_text_message_json, clipplus_derive_group_id, clipplus_free_string,
    clipplus_get_status_json,
};
use clipplus_ffi::{
    clipplus_create_text_message_json as reexported_create_text_message_json,
    clipplus_derive_group_id as reexported_derive_group_id,
    clipplus_free_string as reexported_free_string,
    clipplus_get_status_json as reexported_get_status_json,
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
