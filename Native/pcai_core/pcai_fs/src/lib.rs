//! PCAI Filesystem Operations - FFI Exports
//!
//! High-performance filesystem operations with C FFI interface for .NET interop.
//! Supports file deletion, text replacement (regex/literal), and batch operations.

use std::ffi::{CStr, CString};
use std::fs;
use std::os::raw::c_char;
use std::path::Path;
use std::time::Instant;

use rayon::prelude::*;
use regex::Regex;
use serde::{Deserialize, Serialize};
use walkdir::WalkDir;

mod ops;

// ================================
// FFI Types
// ================================

/// Status codes for FFI operations
#[repr(C)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PcaiStatus {
    Success = 0,
    NullPointer = 1,
    InvalidUtf8 = 2,
    IoError = 3,
    PathNotFound = 4,
    PermissionDenied = 5,
}

/// String buffer for returning JSON data to C#
#[repr(C)]
pub struct PcaiStringBuffer {
    pub data: *mut c_char,
    pub len: usize,
}

impl PcaiStringBuffer {
    /// Create empty buffer
    fn empty() -> Self {
        Self {
            data: std::ptr::null_mut(),
            len: 0,
        }
    }

    /// Create buffer from Rust string
    fn from_string(s: String) -> Self {
        match CString::new(s) {
            Ok(cstr) => {
                let len = cstr.as_bytes().len();
                let data = cstr.into_raw();
                Self { data, len }
            }
            Err(_) => Self::empty(),
        }
    }
}

// ================================
// Result Types
// ================================

#[derive(Debug, Serialize, Deserialize)]
struct ReplaceResult {
    status: String,
    files_scanned: usize,
    files_changed: usize,
    matches_replaced: usize,
    elapsed_ms: u64,
    #[serde(skip_serializing_if = "Option::is_none")]
    error: Option<String>,
}

impl ReplaceResult {
    fn success(files_scanned: usize, files_changed: usize, matches_replaced: usize, elapsed_ms: u64) -> Self {
        Self {
            status: "success".to_string(),
            files_scanned,
            files_changed,
            matches_replaced,
            elapsed_ms,
            error: None,
        }
    }

    fn error(msg: String) -> Self {
        Self {
            status: "error".to_string(),
            files_scanned: 0,
            files_changed: 0,
            matches_replaced: 0,
            elapsed_ms: 0,
            error: Some(msg),
        }
    }
}

// ================================
// Helper Functions
// ================================

/// Safely convert C string to Rust &str
unsafe fn c_str_to_str<'a>(ptr: *const c_char) -> Result<&'a str, PcaiStatus> {
    if ptr.is_null() {
        return Err(PcaiStatus::NullPointer);
    }
    CStr::from_ptr(ptr)
        .to_str()
        .map_err(|_| PcaiStatus::InvalidUtf8)
}

/// Create backup file with .bak extension
fn create_backup(path: &Path) -> std::io::Result<()> {
    let backup_path = path.with_extension(
        format!(
            "{}.bak",
            path.extension()
                .and_then(|s| s.to_str())
                .unwrap_or("")
        )
    );
    fs::copy(path, backup_path)?;
    Ok(())
}

/// Perform text replacement in a single file
fn replace_in_file_impl(
    file_path: &Path,
    pattern: &str,
    replacement: &str,
    is_regex: bool,
    backup: bool,
) -> Result<usize, String> {
    // Read file contents
    let content = fs::read_to_string(file_path)
        .map_err(|e| format!("Failed to read file: {}", e))?;

    // Perform replacement
    let (new_content, count) = if is_regex {
        let re = Regex::new(pattern)
            .map_err(|e| format!("Invalid regex pattern: {}", e))?;
        let new = re.replace_all(&content, replacement).to_string();
        let matches = re.find_iter(&content).count();
        (new, matches)
    } else {
        let matches = content.matches(pattern).count();
        let new = content.replace(pattern, replacement);
        (new, matches)
    };

    // Only write if changes were made
    if count > 0 {
        // Create backup if requested
        if backup {
            create_backup(file_path)
                .map_err(|e| format!("Failed to create backup: {}", e))?;
        }

        // Write modified content
        fs::write(file_path, new_content)
            .map_err(|e| format!("Failed to write file: {}", e))?;
    }

    Ok(count)
}

/// Check if file matches glob pattern
fn matches_pattern(file_name: &str, pattern: &str) -> bool {
    // Simple glob matching (* and ?)
    if pattern == "*" || pattern == "*.*" {
        return true;
    }

    // Exact match
    if pattern == file_name {
        return true;
    }

    // Wildcard patterns
    if pattern.contains('*') {
        let parts: Vec<&str> = pattern.split('*').collect();
        if parts.len() == 2 {
            let prefix = parts[0];
            let suffix = parts[1];
            return file_name.starts_with(prefix) && file_name.ends_with(suffix);
        }
    }

    false
}

// ================================
// FFI Exports
// ================================

/// Get crate version (returns 1 for v0.1.0)
#[no_mangle]
pub extern "C" fn pcai_fs_version() -> u32 {
    1
}

/// Delete filesystem item (file or directory)
///
/// # Safety
/// - `path` must be a valid null-terminated UTF-8 string
/// - Caller must ensure path is properly encoded
#[no_mangle]
pub unsafe extern "C" fn pcai_delete_fs_item(
    path: *const c_char,
    recursive: bool,
) -> PcaiStatus {
    // Convert C string to Rust
    let path_str = match c_str_to_str(path) {
        Ok(s) => s,
        Err(e) => return e,
    };

    let path_obj = Path::new(path_str);

    // Check if path exists
    if !path_obj.exists() {
        return PcaiStatus::PathNotFound;
    }

    // Delete based on type
    let result = if path_obj.is_dir() {
        if recursive {
            fs::remove_dir_all(path_obj)
        } else {
            fs::remove_dir(path_obj)
        }
    } else {
        fs::remove_file(path_obj)
    };

    match result {
        Ok(_) => PcaiStatus::Success,
        Err(e) => match e.kind() {
            std::io::ErrorKind::PermissionDenied => PcaiStatus::PermissionDenied,
            std::io::ErrorKind::NotFound => PcaiStatus::PathNotFound,
            _ => PcaiStatus::IoError,
        },
    }
}

/// Replace text in a single file
///
/// # Safety
/// - All pointer parameters must be valid null-terminated UTF-8 strings
/// - Caller must ensure strings are properly encoded
#[no_mangle]
pub unsafe extern "C" fn pcai_replace_in_file(
    file_path: *const c_char,
    pattern: *const c_char,
    replacement: *const c_char,
    is_regex: bool,
    backup: bool,
) -> PcaiStatus {
    // Convert C strings
    let file_path_str = match c_str_to_str(file_path) {
        Ok(s) => s,
        Err(e) => return e,
    };
    let pattern_str = match c_str_to_str(pattern) {
        Ok(s) => s,
        Err(e) => return e,
    };
    let replacement_str = match c_str_to_str(replacement) {
        Ok(s) => s,
        Err(e) => return e,
    };

    let path = Path::new(file_path_str);

    // Check file exists
    if !path.exists() {
        return PcaiStatus::PathNotFound;
    }

    // Perform replacement
    match replace_in_file_impl(path, pattern_str, replacement_str, is_regex, backup) {
        Ok(_) => PcaiStatus::Success,
        Err(_) => PcaiStatus::IoError,
    }
}

/// Replace text in multiple files (parallel processing)
///
/// Returns JSON string with operation results:
/// ```json
/// {
///   "status": "success",
///   "files_scanned": 42,
///   "files_changed": 5,
///   "matches_replaced": 12,
///   "elapsed_ms": 150
/// }
/// ```
///
/// # Safety
/// - All pointer parameters must be valid null-terminated UTF-8 strings
/// - Caller must free returned buffer with `pcai_free_string_buffer`
#[no_mangle]
pub unsafe extern "C" fn pcai_replace_in_files(
    root_path: *const c_char,
    file_pattern: *const c_char,
    content_pattern: *const c_char,
    replacement: *const c_char,
    is_regex: bool,
    backup: bool,
) -> PcaiStringBuffer {
    let start = Instant::now();

    // Convert C strings
    let root_str = match c_str_to_str(root_path) {
        Ok(s) => s,
        Err(_) => {
            let result = ReplaceResult::error("Invalid root path pointer".to_string());
            let json = serde_json::to_string(&result).unwrap_or_default();
            return PcaiStringBuffer::from_string(json);
        }
    };
    let file_pat = match c_str_to_str(file_pattern) {
        Ok(s) => s,
        Err(_) => {
            let result = ReplaceResult::error("Invalid file pattern pointer".to_string());
            let json = serde_json::to_string(&result).unwrap_or_default();
            return PcaiStringBuffer::from_string(json);
        }
    };
    let content_pat = match c_str_to_str(content_pattern) {
        Ok(s) => s,
        Err(_) => {
            let result = ReplaceResult::error("Invalid content pattern pointer".to_string());
            let json = serde_json::to_string(&result).unwrap_or_default();
            return PcaiStringBuffer::from_string(json);
        }
    };
    let repl = match c_str_to_str(replacement) {
        Ok(s) => s,
        Err(_) => {
            let result = ReplaceResult::error("Invalid replacement pointer".to_string());
            let json = serde_json::to_string(&result).unwrap_or_default();
            return PcaiStringBuffer::from_string(json);
        }
    };

    // Collect all matching files
    let mut files = Vec::new();
    for entry in WalkDir::new(root_str)
        .follow_links(false)
        .into_iter()
        .filter_map(|e| e.ok())
    {
        if entry.file_type().is_file() {
            if let Some(name) = entry.file_name().to_str() {
                if matches_pattern(name, file_pat) {
                    files.push(entry.path().to_path_buf());
                }
            }
        }
    }

    let files_scanned = files.len();

    // Process files in parallel
    let results: Vec<(bool, usize)> = files
        .par_iter()
        .map(|path| {
            match replace_in_file_impl(path, content_pat, repl, is_regex, backup) {
                Ok(count) => (count > 0, count),
                Err(_) => (false, 0),
            }
        })
        .collect();

    // Aggregate results
    let files_changed = results.iter().filter(|(changed, _)| *changed).count();
    let matches_replaced = results.iter().map(|(_, count)| count).sum();
    let elapsed_ms = start.elapsed().as_millis() as u64;

    let result = ReplaceResult::success(
        files_scanned,
        files_changed,
        matches_replaced,
        elapsed_ms,
    );

    let json = serde_json::to_string(&result).unwrap_or_else(|_| {
        r#"{"status":"error","error":"JSON serialization failed"}"#.to_string()
    });

    PcaiStringBuffer::from_string(json)
}

/// Free string buffer allocated by Rust
///
/// # Safety
/// - `buffer` must have been allocated by `pcai_replace_in_files`
/// - Must not be called twice on the same buffer
#[no_mangle]
pub unsafe extern "C" fn pcai_free_string_buffer(buffer: PcaiStringBuffer) {
    if !buffer.data.is_null() {
        let _ = CString::from_raw(buffer.data);
    }
}

// ================================
// Tests
// ================================

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn to_c_string(s: &str) -> CString {
        CString::new(s).unwrap()
    }

    #[test]
    fn test_version() {
        assert_eq!(pcai_fs_version(), 1);
    }

    #[test]
    fn test_pattern_matching() {
        assert!(matches_pattern("test.txt", "*.txt"));
        assert!(matches_pattern("readme.md", "*.md"));
        assert!(matches_pattern("file.rs", "file.rs"));
        assert!(!matches_pattern("test.txt", "*.md"));
    }

    #[test]
    fn test_delete_nonexistent() {
        let path = to_c_string("/nonexistent/path/to/nowhere");
        unsafe {
            let result = pcai_delete_fs_item(path.as_ptr(), false);
            assert_eq!(result, PcaiStatus::PathNotFound);
        }
    }

    #[test]
    fn test_null_pointer_handling() {
        unsafe {
            let result = pcai_delete_fs_item(std::ptr::null(), false);
            assert_eq!(result, PcaiStatus::NullPointer);
        }
    }
}
