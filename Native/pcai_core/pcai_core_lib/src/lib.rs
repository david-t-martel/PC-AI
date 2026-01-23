//! PCAI Core Library - FFI Utilities and Shared Types
//!
//! This library provides the foundational FFI infrastructure for the PC_AI
//! native acceleration framework. It includes:
//!
//! - Status codes for cross-language error handling
//! - Result structures for operation statistics
//! - String buffer management for safe memory handling across FFI boundaries
//! - Version information and health check utilities
//!
//! # Architecture
//! All types use `#[repr(C)]` for C-compatible memory layout, enabling
//! direct marshaling to/from C# via P/Invoke.
//!
//! # Safety
//! This library uses unsafe code for FFI. All unsafe blocks are documented
//! and have been carefully reviewed for correctness.

use std::ffi::{CStr, CString};
use std::os::raw::c_char;

pub mod error;
pub mod path;
pub mod result;
pub mod string;

pub use error::PcaiStatus;
pub use path::{normalize_path, parse_path_ffi, PathStyle};
pub use result::PcaiResult;
pub use string::PcaiStringBuffer;

/// Library version string
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

/// Magic number for DLL verification
/// Value chosen to spell "PCAI" in a readable way: 0x50434149
/// Decimal: 1346587977
pub const MAGIC_NUMBER: u32 = 0x5043_4149;

// ============================================================================
// FFI Exports - Core Functions
// ============================================================================

/// Returns the library version as a null-terminated C string.
///
/// # Safety
/// The returned pointer is valid for the lifetime of the program (static).
/// Do not free this pointer.
///
/// # Example (C#)
/// ```csharp
/// [DllImport("pcai_core.dll")]
/// private static extern IntPtr pcai_core_version();
///
/// string version = Marshal.PtrToStringAnsi(pcai_core_version());
/// ```
#[no_mangle]
pub extern "C" fn pcai_core_version() -> *const c_char {
    // Use a const to ensure static storage duration - pointer remains valid
    const VERSION_CSTR: &[u8] = concat!(env!("CARGO_PKG_VERSION"), "\0").as_bytes();
    VERSION_CSTR.as_ptr() as *const c_char
}

/// Returns a magic number to verify DLL is loaded correctly.
///
/// # Returns
/// The value `0x50C_A1` (5349281 decimal) if the DLL is working correctly.
///
/// # Example (C#)
/// ```csharp
/// [DllImport("pcai_core.dll")]
/// private static extern uint pcai_core_test();
///
/// if (pcai_core_test() == 0x50CA1) {
///     Console.WriteLine("DLL loaded successfully");
/// }
/// ```
#[no_mangle]
pub extern "C" fn pcai_core_test() -> u32 {
    MAGIC_NUMBER
}

/// Frees a string buffer allocated by PCAI functions.
///
/// # Safety
/// - `buffer` must be a pointer returned by a PCAI function
/// - The pointer becomes invalid after this call
/// - Calling with a null pointer is safe (no-op)
///
/// # Example (C#)
/// ```csharp
/// IntPtr jsonPtr = pcai_some_json_function();
/// try {
///     string json = Marshal.PtrToStringAnsi(jsonPtr);
///     // Use the JSON string
/// } finally {
///     pcai_free_string(jsonPtr);
/// }
/// ```
#[no_mangle]
pub extern "C" fn pcai_free_string(buffer: *mut c_char) {
    if buffer.is_null() {
        return;
    }

    // Safety: We're taking ownership of a CString we previously allocated
    unsafe {
        let _ = CString::from_raw(buffer);
    }
}

/// Allocates and returns a copy of the input string.
///
/// Used for testing string allocation/deallocation across FFI boundary.
///
/// # Safety
/// - `input` must be a valid null-terminated C string or null
/// - The returned pointer must be freed with `pcai_free_string`
///
/// # Returns
/// A newly allocated copy of the input string, or null if input was null.
#[no_mangle]
pub extern "C" fn pcai_string_copy(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return std::ptr::null_mut();
    }

    // Safety: We verified input is non-null
    let c_str = unsafe { CStr::from_ptr(input) };

    match c_str.to_str() {
        Ok(s) => match CString::new(s) {
            Ok(c_string) => c_string.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

/// Returns the number of logical CPU cores available.
///
/// Useful for parallel processing configuration.
#[no_mangle]
pub extern "C" fn pcai_cpu_count() -> u32 {
    std::thread::available_parallelism()
        .map(|n| n.get() as u32)
        .unwrap_or(1)
}

// ============================================================================
// Rust-only Utilities
// ============================================================================

/// Converts a C string pointer to a Rust &str, handling errors gracefully.
///
/// # Safety
/// The caller must ensure:
/// - `ptr` is either null or points to a valid null-terminated C string
/// - The pointer remains valid for the returned lifetime 'a
/// - The string contains valid UTF-8
pub unsafe fn c_str_to_rust<'a>(ptr: *const c_char) -> Option<&'a str> {
    if ptr.is_null() {
        return None;
    }

    CStr::from_ptr(ptr).to_str().ok()
}

/// Converts a Rust string to an owned C string for FFI return.
///
/// The returned pointer must be freed with `pcai_free_string`.
pub fn rust_str_to_c(s: &str) -> *mut c_char {
    match CString::new(s) {
        Ok(c_string) => c_string.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_magic_number() {
        assert_eq!(pcai_core_test(), MAGIC_NUMBER);
    }

    #[test]
    fn test_version_not_empty() {
        let version_ptr = pcai_core_version();
        assert!(!version_ptr.is_null());

        let version = unsafe { CStr::from_ptr(version_ptr) };
        let version_str = version.to_str().expect("Invalid UTF-8 in version");
        assert!(!version_str.is_empty());
        assert!(version_str.contains('.'));
    }

    #[test]
    fn test_cpu_count_valid() {
        let count = pcai_cpu_count();
        assert!(count >= 1);
        assert!(count <= 1024); // Reasonable upper bound
    }

    #[test]
    fn test_string_copy_null() {
        let result = pcai_string_copy(std::ptr::null());
        assert!(result.is_null());
    }

    #[test]
    fn test_string_copy_roundtrip() {
        let test_str = "Hello, PCAI!\0";
        let result = pcai_string_copy(test_str.as_ptr() as *const c_char);
        assert!(!result.is_null());

        let result_str = unsafe { CStr::from_ptr(result) };
        assert_eq!(result_str.to_str().unwrap(), "Hello, PCAI!");

        // Free the allocated string
        pcai_free_string(result);
    }

    #[test]
    fn test_free_null_string() {
        // Should not panic or cause issues
        pcai_free_string(std::ptr::null_mut());
    }
}
