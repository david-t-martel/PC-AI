//! String buffer utilities for FFI.
//!
//! Provides safe string handling across the FFI boundary, including
//! allocation, deallocation, and buffer management.

use std::ffi::CString;
use std::os::raw::c_char;

use crate::error::PcaiStatus;

/// A string buffer for returning string data across FFI boundaries.
///
/// This structure holds a pointer to allocated string data and its length.
/// The caller is responsible for freeing the buffer using `pcai_free_string_buffer`.
///
/// # C# Mapping
/// ```csharp
/// [StructLayout(LayoutKind.Sequential)]
/// public struct PcaiStringBuffer {
///     public PcaiStatus Status;
///     public IntPtr Data;
///     public UIntPtr Length;
/// }
/// ```
#[repr(C)]
#[derive(Debug)]
pub struct PcaiStringBuffer {
    /// Operation status
    pub status: PcaiStatus,

    /// Pointer to null-terminated string data (UTF-8 encoded)
    pub data: *mut c_char,

    /// Length of the string in bytes (excluding null terminator)
    pub length: usize,
}

impl PcaiStringBuffer {
    /// Creates a new string buffer from a Rust string.
    ///
    /// The string is copied and null-terminated. The caller is responsible
    /// for freeing the buffer using `pcai_free_string_buffer`.
    pub fn from_string(s: &str) -> Self {
        match CString::new(s) {
            Ok(c_string) => {
                let len = c_string.as_bytes().len();
                Self {
                    status: PcaiStatus::Success,
                    data: c_string.into_raw(),
                    length: len,
                }
            }
            Err(_) => Self::error(PcaiStatus::InvalidUtf8),
        }
    }

    /// Creates an error buffer with the given status.
    pub fn error(status: PcaiStatus) -> Self {
        Self {
            status,
            data: std::ptr::null_mut(),
            length: 0,
        }
    }

    /// Creates a null/empty buffer.
    pub fn null() -> Self {
        Self {
            status: PcaiStatus::NullPointer,
            data: std::ptr::null_mut(),
            length: 0,
        }
    }

    /// Returns true if this buffer contains valid data.
    pub fn is_valid(&self) -> bool {
        self.status.is_success() && !self.data.is_null()
    }
}

impl Default for PcaiStringBuffer {
    fn default() -> Self {
        Self::null()
    }
}

// NOTE: Drop is intentionally NOT implemented for PcaiStringBuffer.
// This type is designed for FFI where ownership transfers to C#.
// The caller MUST use pcai_free_string_buffer() to free the memory.
// Implementing Drop would cause double-free when both Rust and C# try to free.

// FFI Exports

/// Creates a string buffer from a C string.
///
/// # Safety
/// - `input` must be a valid null-terminated C string or null
/// - The returned buffer must be freed with `pcai_free_string_buffer`
#[no_mangle]
pub extern "C" fn pcai_create_string_buffer(input: *const c_char) -> PcaiStringBuffer {
    if input.is_null() {
        return PcaiStringBuffer::null();
    }

    // Safety: We verified input is non-null
    let c_str = unsafe { std::ffi::CStr::from_ptr(input) };

    match c_str.to_str() {
        Ok(s) => PcaiStringBuffer::from_string(s),
        Err(_) => PcaiStringBuffer::error(PcaiStatus::InvalidUtf8),
    }
}

/// Frees a string buffer allocated by PCAI functions.
///
/// # Safety
/// - `buffer` must be a buffer returned by a PCAI function
/// - The buffer becomes invalid after this call
/// - Calling with a null data pointer is safe (no-op)
#[no_mangle]
pub extern "C" fn pcai_free_string_buffer(buffer: *mut PcaiStringBuffer) {
    if buffer.is_null() {
        return;
    }

    // Safety: We verified buffer is non-null
    let buf = unsafe { &mut *buffer };

    if !buf.data.is_null() {
        // Safety: We're taking ownership of a CString we previously allocated
        unsafe {
            let _ = CString::from_raw(buf.data);
        }
        buf.data = std::ptr::null_mut();
        buf.length = 0;
    }
}

/// Utility function to convert JSON to a string buffer for FFI return.
///
/// This is commonly used by modules that return JSON results.
pub fn json_to_buffer<T: serde::Serialize>(value: &T) -> PcaiStringBuffer {
    match serde_json::to_string(value) {
        Ok(json) => PcaiStringBuffer::from_string(&json),
        Err(_) => PcaiStringBuffer::error(PcaiStatus::JsonError),
    }
}

/// Utility function to convert JSON with pretty printing.
pub fn json_to_buffer_pretty<T: serde::Serialize>(value: &T) -> PcaiStringBuffer {
    match serde_json::to_string_pretty(value) {
        Ok(json) => PcaiStringBuffer::from_string(&json),
        Err(_) => PcaiStringBuffer::error(PcaiStatus::JsonError),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_string_buffer_from_string() {
        let buf = PcaiStringBuffer::from_string("Hello, World!");
        assert!(buf.is_valid());
        assert_eq!(buf.length, 13);
        assert!(!buf.data.is_null());

        // Clean up
        let _ = unsafe { CString::from_raw(buf.data) };
    }

    #[test]
    fn test_string_buffer_error() {
        let buf = PcaiStringBuffer::error(PcaiStatus::PathNotFound);
        assert!(!buf.is_valid());
        assert!(buf.data.is_null());
        assert_eq!(buf.status, PcaiStatus::PathNotFound);
    }

    #[test]
    fn test_string_buffer_null() {
        let buf = PcaiStringBuffer::null();
        assert!(!buf.is_valid());
        assert!(buf.data.is_null());
        assert_eq!(buf.status, PcaiStatus::NullPointer);
    }

    #[test]
    fn test_create_buffer_null_input() {
        let buf = pcai_create_string_buffer(std::ptr::null());
        assert!(!buf.is_valid());
        assert_eq!(buf.status, PcaiStatus::NullPointer);
    }

    #[test]
    fn test_json_to_buffer() {
        #[derive(serde::Serialize)]
        struct TestData {
            name: &'static str,
            value: i32,
        }

        let data = TestData {
            name: "test",
            value: 42,
        };

        let buf = json_to_buffer(&data);
        assert!(buf.is_valid());

        // Verify JSON content
        let json = unsafe { std::ffi::CStr::from_ptr(buf.data) };
        let json_str = json.to_str().unwrap();
        assert!(json_str.contains("\"name\":\"test\""));
        assert!(json_str.contains("\"value\":42"));

        // Clean up
        let _ = unsafe { CString::from_raw(buf.data) };
    }
}
