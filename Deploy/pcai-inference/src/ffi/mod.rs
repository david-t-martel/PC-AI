//! FFI exports for PowerShell integration

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

/// Initialize the inference engine
/// Returns a handle (pointer) to the engine instance
#[no_mangle]
pub extern "C" fn pcai_init(config_json: *const c_char) -> *mut std::ffi::c_void {
    if config_json.is_null() {
        tracing::error!("pcai_init: config_json is null");
        return std::ptr::null_mut();
    }

    // TODO: Implement initialization
    tracing::warn!("pcai_init not yet implemented");
    std::ptr::null_mut()
}

/// Generate text from a prompt
/// Returns a JSON string with the response (caller must free with pcai_free_string)
#[no_mangle]
pub extern "C" fn pcai_generate(
    handle: *mut std::ffi::c_void,
    prompt: *const c_char,
) -> *mut c_char {
    if handle.is_null() || prompt.is_null() {
        tracing::error!("pcai_generate: null pointer");
        return std::ptr::null_mut();
    }

    // TODO: Implement generation
    tracing::warn!("pcai_generate not yet implemented");
    std::ptr::null_mut()
}

/// Free a string returned by the FFI
#[no_mangle]
pub extern "C" fn pcai_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }

    unsafe {
        let _ = CString::from_raw(s);
    }
}

/// Shutdown the inference engine and free resources
#[no_mangle]
pub extern "C" fn pcai_shutdown(handle: *mut std::ffi::c_void) {
    if handle.is_null() {
        return;
    }

    // TODO: Implement shutdown
    tracing::warn!("pcai_shutdown not yet implemented");
}

/// Get the last error message
#[no_mangle]
pub extern "C" fn pcai_last_error() -> *const c_char {
    // TODO: Implement error tracking
    std::ptr::null()
}
