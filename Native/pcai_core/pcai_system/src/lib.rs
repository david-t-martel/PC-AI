//! pcai_system - System Module for PC_AI
//!
//! This module provides PATH environment variable analysis and log file searching
//! with optimized FFI exports for C# integration.

pub mod logs;
pub mod path;

use pcai_core_lib::{PcaiStatus, PcaiStringBuffer};
use std::ffi::CStr;
use std::os::raw::c_char;

// Re-export types for external use
pub use logs::{LogSearchStats, LogSearchOptions};
pub use path::PathAnalysisStats;

// ============================================================================
// Version and Test Functions
// ============================================================================

/// Version number encoded as 0xMMmmpp (major.minor.patch)
/// Current version: 1.0.0
const VERSION: u32 = 0x010000;

/// Magic number for DLL validation: "SYST" in ASCII
const MAGIC: u32 = 0x53595354;

/// Get the system module version
#[no_mangle]
pub extern "C" fn pcai_system_version() -> u32 {
    VERSION
}

/// Test function to verify DLL is loaded correctly
#[no_mangle]
pub extern "C" fn pcai_system_test() -> u32 {
    MAGIC
}

// ============================================================================
// PATH Analysis Functions
// ============================================================================

/// Analyze the PATH environment variable for issues
///
/// Returns statistics about the PATH including duplicate count, non-existent
/// directories, empty entries, and trailing slashes.
#[no_mangle]
pub extern "C" fn pcai_analyze_path() -> PathAnalysisStats {
    let (stats, _) = path::analyze_path();
    stats
}

/// Analyze PATH and return detailed JSON report
///
/// Returns a JSON string with comprehensive PATH analysis including:
/// - Health status
/// - All detected issues with severity
/// - Duplicate groups
/// - Non-existent paths
/// - Recommendations for cleanup
#[no_mangle]
pub extern "C" fn pcai_analyze_path_json() -> PcaiStringBuffer {
    let (_, json) = path::analyze_path();

    match serde_json::to_string_pretty(&json) {
        Ok(s) => PcaiStringBuffer::from_string(&s),
        Err(e) => {
            let error_json = format!(r#"{{"status":"Error","error":"{}"}}"#, e);
            PcaiStringBuffer::from_string(&error_json)
        }
    }
}

// ============================================================================
// Log Search Functions
// ============================================================================

/// Search log files for a pattern
///
/// # Arguments
/// * `root_path` - Directory to search in
/// * `pattern` - Regex pattern to search for
/// * `file_pattern` - Glob pattern for log files (e.g., "*.log"), or null for default
/// * `case_sensitive` - Whether search is case-sensitive
/// * `context_lines` - Number of context lines before/after matches
/// * `max_matches` - Maximum number of matches to return
///
/// # Returns
/// LogSearchStats with search statistics
#[no_mangle]
pub extern "C" fn pcai_search_logs(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    case_sensitive: bool,
    context_lines: u32,
    max_matches: u32,
) -> LogSearchStats {
    // Validate pointers
    if root_path.is_null() || pattern.is_null() {
        return LogSearchStats::error(PcaiStatus::NullPointer);
    }

    // Convert C strings to Rust strings
    let root_path_str = unsafe {
        match CStr::from_ptr(root_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return LogSearchStats::error(PcaiStatus::InvalidArgument),
        }
    };

    let pattern_str = unsafe {
        match CStr::from_ptr(pattern).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => return LogSearchStats::error(PcaiStatus::InvalidArgument),
        }
    };

    let file_pattern_str = if file_pattern.is_null() {
        None
    } else {
        unsafe {
            match CStr::from_ptr(file_pattern).to_str() {
                Ok(s) => Some(s.to_string()),
                Err(_) => None,
            }
        }
    };

    let options = LogSearchOptions {
        pattern: pattern_str,
        root_path: root_path_str,
        file_pattern: file_pattern_str,
        case_sensitive,
        context_lines: context_lines as usize,
        max_matches: max_matches as usize,
        max_files: 1000,
    };

    let (stats, _) = logs::search_logs(&options);
    stats
}

/// Search log files and return JSON results
///
/// # Arguments
/// * `root_path` - Directory to search in
/// * `pattern` - Regex pattern to search for
/// * `file_pattern` - Glob pattern for log files (e.g., "*.log"), or null for default
/// * `case_sensitive` - Whether search is case-sensitive
/// * `context_lines` - Number of context lines before/after matches
/// * `max_matches` - Maximum number of matches to return
///
/// # Returns
/// PcaiStringBuffer containing JSON results
#[no_mangle]
pub extern "C" fn pcai_search_logs_json(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    case_sensitive: bool,
    context_lines: u32,
    max_matches: u32,
) -> PcaiStringBuffer {
    // Validate pointers
    if root_path.is_null() || pattern.is_null() {
        let error_json = r#"{"status":"Error","error":"Null pointer provided"}"#;
        return PcaiStringBuffer::from_string(error_json);
    }

    // Convert C strings to Rust strings
    let root_path_str = unsafe {
        match CStr::from_ptr(root_path).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                let error_json = r#"{"status":"Error","error":"Invalid UTF-8 in root_path"}"#;
                return PcaiStringBuffer::from_string(error_json);
            }
        }
    };

    let pattern_str = unsafe {
        match CStr::from_ptr(pattern).to_str() {
            Ok(s) => s.to_string(),
            Err(_) => {
                let error_json = r#"{"status":"Error","error":"Invalid UTF-8 in pattern"}"#;
                return PcaiStringBuffer::from_string(error_json);
            }
        }
    };

    let file_pattern_str = if file_pattern.is_null() {
        None
    } else {
        unsafe {
            match CStr::from_ptr(file_pattern).to_str() {
                Ok(s) => Some(s.to_string()),
                Err(_) => None,
            }
        }
    };

    let options = LogSearchOptions {
        pattern: pattern_str,
        root_path: root_path_str,
        file_pattern: file_pattern_str,
        case_sensitive,
        context_lines: context_lines as usize,
        max_matches: max_matches as usize,
        max_files: 1000,
    };

    let (_, json) = logs::search_logs(&options);

    match serde_json::to_string_pretty(&json) {
        Ok(s) => PcaiStringBuffer::from_string(&s),
        Err(e) => {
            let error_json = format!(r#"{{"status":"Error","error":"{}"}}"#, e);
            PcaiStringBuffer::from_string(&error_json)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        assert_eq!(pcai_system_version(), 0x010000);
    }

    #[test]
    fn test_magic() {
        assert_eq!(pcai_system_test(), 0x53595354); // "SYST"
    }

    #[test]
    fn test_analyze_path() {
        let stats = pcai_analyze_path();
        assert_eq!(stats.status, PcaiStatus::Success);
        assert!(stats.total_entries > 0);
    }

    #[test]
    fn test_analyze_path_json() {
        let buffer = pcai_analyze_path_json();
        assert!(buffer.is_valid());
        // Convert buffer to string for verification
        let json = unsafe {
            std::ffi::CStr::from_ptr(buffer.data)
                .to_str()
                .unwrap_or("")
        };
        assert!(json.contains("status"));
        assert!(json.contains("Success"));
    }

    #[test]
    fn test_search_logs_null_pointer() {
        let stats = pcai_search_logs(
            std::ptr::null(),
            std::ptr::null(),
            std::ptr::null(),
            false,
            0,
            100,
        );
        assert_eq!(stats.status, PcaiStatus::NullPointer);
    }
}
