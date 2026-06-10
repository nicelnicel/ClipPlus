use std::ffi::CStr;
use std::os::raw::c_char;
use std::panic;
use std::ptr;

use clipplus_crypto::key::SharedKeyMaterial;
use clipplus_diagnostics::status::RuntimeStatus;
use clipplus_transport::message::NativeClipboardMessage;

use crate::types::{free_c_string, string_to_c_ptr};

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
