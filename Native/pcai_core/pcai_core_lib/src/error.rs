//! Error types and status codes for FFI operations.
//!
//! All status codes use `#[repr(C)]` for direct marshaling to C#.

use std::os::raw::c_char;

/// Status codes returned by PCAI operations.
///
/// These codes are designed for cross-language compatibility and follow
/// a consistent pattern where 0 = success and non-zero = error.
///
/// # C# Mapping
/// ```csharp
/// public enum PcaiStatus : uint {
///     Success = 0,
///     InvalidArgument = 1,
///     NullPointer = 2,
///     // ...
/// }
/// ```
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PcaiStatus {
    /// Operation completed successfully
    Success = 0,

    /// Invalid argument provided (e.g., negative value where positive required)
    InvalidArgument = 1,

    /// Null pointer was passed where a valid pointer was required
    NullPointer = 2,

    /// Invalid UTF-8 encoding in string parameter
    InvalidUtf8 = 3,

    /// Path does not exist
    PathNotFound = 4,

    /// Permission denied accessing path or resource
    PermissionDenied = 5,

    /// I/O error during file operation
    IoError = 6,

    /// Operation was cancelled
    Cancelled = 7,

    /// Timeout expired
    Timeout = 8,

    /// Internal error (bug in the library)
    InternalError = 9,

    /// Feature not implemented
    NotImplemented = 10,

    /// Out of memory
    OutOfMemory = 11,

    /// JSON serialization/deserialization error
    JsonError = 12,

    /// Unknown or unclassified error
    Unknown = 255,
}

impl PcaiStatus {
    /// Returns true if this status indicates success.
    #[inline]
    pub fn is_success(self) -> bool {
        self == PcaiStatus::Success
    }

    /// Returns true if this status indicates an error.
    #[inline]
    pub fn is_error(self) -> bool {
        self != PcaiStatus::Success
    }

    /// Converts an I/O error kind to the appropriate status code.
    pub fn from_io_error(error: &std::io::Error) -> Self {
        use std::io::ErrorKind;
        match error.kind() {
            ErrorKind::NotFound => PcaiStatus::PathNotFound,
            ErrorKind::PermissionDenied => PcaiStatus::PermissionDenied,
            ErrorKind::TimedOut => PcaiStatus::Timeout,
            ErrorKind::OutOfMemory => PcaiStatus::OutOfMemory,
            _ => PcaiStatus::IoError,
        }
    }

    /// Returns a human-readable description of this status.
    pub fn description(self) -> &'static str {
        match self {
            PcaiStatus::Success => "Operation completed successfully",
            PcaiStatus::InvalidArgument => "Invalid argument provided",
            PcaiStatus::NullPointer => "Null pointer provided",
            PcaiStatus::InvalidUtf8 => "Invalid UTF-8 encoding",
            PcaiStatus::PathNotFound => "Path does not exist",
            PcaiStatus::PermissionDenied => "Permission denied",
            PcaiStatus::IoError => "I/O error",
            PcaiStatus::Cancelled => "Operation cancelled",
            PcaiStatus::Timeout => "Operation timed out",
            PcaiStatus::InternalError => "Internal error",
            PcaiStatus::NotImplemented => "Feature not implemented",
            PcaiStatus::OutOfMemory => "Out of memory",
            PcaiStatus::JsonError => "JSON serialization error",
            PcaiStatus::Unknown => "Unknown error",
        }
    }
}

impl Default for PcaiStatus {
    fn default() -> Self {
        PcaiStatus::Success
    }
}

impl From<std::io::Error> for PcaiStatus {
    fn from(error: std::io::Error) -> Self {
        PcaiStatus::from_io_error(&error)
    }
}

// FFI Exports

/// Returns a human-readable description of a status code.
///
/// # Safety
/// The returned pointer is valid for the lifetime of the program (static).
/// Do not free this pointer.
#[no_mangle]
pub extern "C" fn pcai_status_description(status: PcaiStatus) -> *const c_char {
    // Return pointer to static null-terminated string
    match status {
        PcaiStatus::Success => "Operation completed successfully\0",
        PcaiStatus::InvalidArgument => "Invalid argument provided\0",
        PcaiStatus::NullPointer => "Null pointer provided\0",
        PcaiStatus::InvalidUtf8 => "Invalid UTF-8 encoding\0",
        PcaiStatus::PathNotFound => "Path does not exist\0",
        PcaiStatus::PermissionDenied => "Permission denied\0",
        PcaiStatus::IoError => "I/O error\0",
        PcaiStatus::Cancelled => "Operation cancelled\0",
        PcaiStatus::Timeout => "Operation timed out\0",
        PcaiStatus::InternalError => "Internal error\0",
        PcaiStatus::NotImplemented => "Feature not implemented\0",
        PcaiStatus::OutOfMemory => "Out of memory\0",
        PcaiStatus::JsonError => "JSON serialization error\0",
        PcaiStatus::Unknown => "Unknown error\0",
    }
    .as_ptr() as *const c_char
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_status_is_success() {
        assert!(PcaiStatus::Success.is_success());
        assert!(!PcaiStatus::InvalidArgument.is_success());
        assert!(!PcaiStatus::Unknown.is_success());
    }

    #[test]
    fn test_status_is_error() {
        assert!(!PcaiStatus::Success.is_error());
        assert!(PcaiStatus::InvalidArgument.is_error());
        assert!(PcaiStatus::Unknown.is_error());
    }

    #[test]
    fn test_status_description_not_empty() {
        for status in [
            PcaiStatus::Success,
            PcaiStatus::InvalidArgument,
            PcaiStatus::NullPointer,
            PcaiStatus::InvalidUtf8,
            PcaiStatus::PathNotFound,
            PcaiStatus::PermissionDenied,
            PcaiStatus::IoError,
            PcaiStatus::Cancelled,
            PcaiStatus::Timeout,
            PcaiStatus::InternalError,
            PcaiStatus::NotImplemented,
            PcaiStatus::OutOfMemory,
            PcaiStatus::JsonError,
            PcaiStatus::Unknown,
        ] {
            assert!(!status.description().is_empty());
        }
    }

    #[test]
    fn test_default_is_success() {
        assert_eq!(PcaiStatus::default(), PcaiStatus::Success);
    }
}
