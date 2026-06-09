use std::ffi::CStr;
use std::ptr;

use clipplus_ffi::api::{clipplus_free_string, clipplus_get_status_json};
use clipplus_ffi::clipplus_get_status_json as reexported_get_status_json;
use serde_json::Value;

unsafe fn take_status_json(ptr: *mut std::ffi::c_char) -> String {
    assert!(!ptr.is_null());

    let json = unsafe { CStr::from_ptr(ptr).to_string_lossy().to_string() };
    unsafe { clipplus_free_string(ptr) };
    json
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
