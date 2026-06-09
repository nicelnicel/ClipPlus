use std::os::raw::c_char;
use std::panic;
use std::ptr;

use clipplus_diagnostics::status::RuntimeStatus;

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
