//! PCAI Core Library - FFI Utilities and Shared Types
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub mod error;
pub mod json;
pub mod path;
pub mod result;
pub mod string;
pub mod search;
pub mod hash;
pub mod system;
pub mod tokenizer;
pub mod telemetry;

pub use error::PcaiStatus;
pub use json::{extract_json_from_markdown, pcai_extract_json, pcai_is_valid_json};
pub use path::{PathStyle, normalize_path, parse_path_ffi};
pub use result::PcaiResult;
pub use string::{PcaiStringBuffer, json_to_buffer_pretty, rust_str_to_c, c_str_to_rust};

include!(concat!(env!("OUT_DIR"), "/version.rs"));

/// Magic number for DLL verification
pub const MAGIC_NUMBER: u32 = 0x5043_4149;

#[no_mangle]
pub extern "C" fn pcai_core_version() -> *const c_char {
    VERSION_CSTR.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn pcai_core_test() -> u32 {
    MAGIC_NUMBER
}

#[no_mangle]
pub extern "C" fn pcai_search_version() -> *const c_char {
    pcai_core_version()
}

#[no_mangle]
pub extern "C" fn pcai_free_string(buffer: *mut c_char) {
    if !buffer.is_null() {
        unsafe { let _ = CString::from_raw(buffer); }
    }
}

#[no_mangle]
pub extern "C" fn pcai_string_copy(input: *const c_char) -> *mut c_char {
    if input.is_null() { return std::ptr::null_mut(); }
    let c_str = unsafe { CStr::from_ptr(input) };
    match c_str.to_str() {
        Ok(s) => rust_str_to_c(s),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn pcai_cpu_count() -> u32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as u32)
        .unwrap_or(1)
}

#[no_mangle]
pub extern "C" fn pcai_estimate_tokens(text: *const c_char) -> libc::size_t {
    let text = unsafe {
        if text.is_null() {
            return 0;
        }
        std::ffi::CStr::from_ptr(text)
    };

    match text.to_str() {
        Ok(s) => tokenizer::estimate_tokens(s),
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn pcai_check_resource_safety(gpu_limit: f32) -> libc::c_int {
    if telemetry::check_resource_safety(gpu_limit) { 1 } else { 0 }
}

#[no_mangle]
pub extern "C" fn pcai_get_system_telemetry_json() -> *mut c_char {
    let tel = telemetry::collect_telemetry();
    match serde_json::to_string(&tel) {
        Ok(json) => {
            let s = std::ffi::CString::new(json).unwrap();
            s.into_raw()
        }
        Err(_) => std::ptr::null_mut(),
    }
}
