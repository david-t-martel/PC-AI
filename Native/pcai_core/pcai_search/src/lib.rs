//! PCAI Search Module - High-Performance File Operations
//!
//! This module provides:
//! - Parallel duplicate file detection with SHA-256 hashing
//! - Fast file search with glob pattern matching
//! - Content search with regex support
//!
//! All operations are optimized for Windows with parallel processing via rayon.

use std::os::raw::c_char;

use pcai_core_lib::string::PcaiStringBuffer;

pub mod content;
pub mod duplicates;
pub mod files;
pub mod walker;

pub use content::{ContentMatch, ContentSearchResult};
pub use duplicates::{DuplicateGroup, DuplicateResult};
pub use files::{FileSearchResult, FoundFile};

/// Library version string
pub const VERSION: &str = env!("CARGO_PKG_VERSION");

// ============================================================================
// FFI Exports - Duplicate Detection
// ============================================================================

/// Finds duplicate files in a directory using parallel SHA-256 hashing.
///
/// # Safety
/// - `root_path` must be a valid null-terminated C string or null
/// - The returned JSON buffer must be freed with `pcai_free_string_buffer`
///
/// # Parameters
/// - `root_path`: Directory to search (UTF-8 encoded)
/// - `min_size`: Minimum file size in bytes to consider (0 = all files)
/// - `include_pattern`: Glob pattern for files to include (null = all files)
/// - `exclude_pattern`: Glob pattern for files to exclude (null = none)
///
/// # Returns
/// JSON string containing duplicate groups and statistics
// #[no_mangle]
pub extern "C" fn pcai_find_duplicates(
    root_path: *const c_char,
    min_size: u64,
    include_pattern: *const c_char,
    exclude_pattern: *const c_char,
) -> PcaiStringBuffer {
    duplicates::find_duplicates_ffi(root_path, min_size, include_pattern, exclude_pattern)
}

// #[no_mangle]
pub extern "C" fn pcai_find_duplicates_stats(
    root_path: *const c_char,
    min_size: u64,
    include_pattern: *const c_char,
    exclude_pattern: *const c_char,
) -> duplicates::DuplicateStats {
    duplicates::find_duplicates_stats_ffi(root_path, min_size, include_pattern, exclude_pattern)
}

// ============================================================================
// FFI Exports - File Search
// ============================================================================

/// Searches for files matching a glob pattern.
///
/// # Safety
/// - `root_path` must be a valid null-terminated C string or null
/// - `pattern` must be a valid null-terminated C string
/// - The returned JSON buffer must be freed with `pcai_free_string_buffer`
///
/// # Parameters
/// - `root_path`: Directory to search (UTF-8 encoded)
/// - `pattern`: Glob pattern to match (e.g., "*.txt", "**/*.rs")
/// - `max_results`: Maximum number of results to return (0 = unlimited)
///
/// # Returns
/// JSON string containing matched files and statistics
// #[no_mangle]
pub extern "C" fn pcai_find_files(
    root_path: *const c_char,
    pattern: *const c_char,
    max_results: u64,
) -> PcaiStringBuffer {
    files::find_files_ffi(root_path, pattern, max_results)
}

// #[no_mangle]
pub extern "C" fn pcai_find_files_stats(
    root_path: *const c_char,
    pattern: *const c_char,
    max_results: u64,
) -> files::FileSearchStats {
    files::find_files_stats_ffi(root_path, pattern, max_results)
}

// ============================================================================
// FFI Exports - Content Search
// ============================================================================

/// Searches file contents for a regex pattern.
///
/// # Safety
/// - `root_path` must be a valid null-terminated C string or null
/// - `pattern` must be a valid null-terminated regex pattern
/// - The returned JSON buffer must be freed with `pcai_free_string_buffer`
///
/// # Parameters
/// - `root_path`: Directory to search (UTF-8 encoded)
/// - `pattern`: Regex pattern to search for
/// - `file_pattern`: Glob pattern for files to search (null = all text files)
/// - `max_results`: Maximum number of matches to return (0 = unlimited)
/// - `context_lines`: Number of lines of context around matches (0 = match only)
///
/// # Returns
/// JSON string containing matches and statistics
// #[no_mangle]
pub extern "C" fn pcai_search_content(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    max_results: u64,
    context_lines: u32,
) -> PcaiStringBuffer {
    content::search_content_ffi(root_path, pattern, file_pattern, max_results, context_lines)
}

// #[no_mangle]
pub extern "C" fn pcai_search_content_stats(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    max_results: u64,
) -> content::ContentSearchStats {
    content::search_content_stats_ffi(root_path, pattern, file_pattern, max_results)
}

// ============================================================================
// Version Info
// ============================================================================

/// Returns the search module version string.
// #[no_mangle]
pub extern "C" fn pcai_search_version() -> *const c_char {
    const VERSION_CSTR: &[u8] = concat!(env!("CARGO_PKG_VERSION"), " (legacy pcai_search)\0").as_bytes();
    VERSION_CSTR.as_ptr() as *const c_char
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    #[test]
    fn test_version_not_empty() {
        let version_ptr = pcai_search_version();
        assert!(!version_ptr.is_null());

        let version = unsafe { CStr::from_ptr(version_ptr) };
        let version_str = version.to_str().expect("Invalid UTF-8 in version");
        assert!(!version_str.is_empty());
        assert!(version_str.contains('.'));
    }
}
