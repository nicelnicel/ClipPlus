use std::ffi::CString;
use std::os::raw::c_char;

pub fn string_to_c_ptr(value: String) -> *mut c_char {
    CString::new(value)
        .expect("FFI string should not contain interior nul bytes")
        .into_raw()
}

/// Releases a C string allocated by [`string_to_c_ptr`].
///
/// # Safety
///
/// `ptr` must be null or a pointer returned by [`string_to_c_ptr`] that has not
/// already been freed. Non-null pointers must be passed back unchanged: callers
/// must not modify the buffer contents, insert an earlier NUL byte, change the
/// string length, or alter the terminating NUL after receiving the pointer.
/// Passing any other pointer, a previously freed pointer, or a modified pointer
/// is undefined behavior.
pub unsafe fn free_c_string(ptr: *mut c_char) {
    if ptr.is_null() {
        return;
    }

    drop(unsafe { CString::from_raw(ptr) });
}
