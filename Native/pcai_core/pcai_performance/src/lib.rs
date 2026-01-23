//! PCAI Performance Module
//!
//! High-performance disk usage analysis and process monitoring via FFI.
//! Provides parallel directory traversal and system information gathering.

pub mod disk;
pub mod memory;
pub mod process;

use pcai_core_lib::{json_to_buffer_pretty, PcaiStatus, PcaiStringBuffer};
use std::ffi::{c_char, CStr};
use std::time::Instant;

// Re-export types for FFI
pub use disk::{DirUsageEntry, DiskUsageStats};
pub use memory::{MemoryStats, MemoryUsageInfo};
pub use process::{ProcessInfo, ProcessStats};

/// FFI: Get disk usage statistics for a directory
///
/// # Safety
/// - `root_path` must be a valid null-terminated UTF-8 string
#[no_mangle]
pub unsafe extern "C" fn pcai_get_disk_usage(
    root_path: *const c_char,
    top_n: u32,
) -> DiskUsageStats {
    if root_path.is_null() {
        return DiskUsageStats::error(PcaiStatus::NullPointer);
    }

    let path_str = match CStr::from_ptr(root_path).to_str() {
        Ok(s) => s,
        Err(_) => return DiskUsageStats::error(PcaiStatus::InvalidUtf8),
    };

    let start = Instant::now();
    match disk::get_disk_usage(path_str, top_n as usize) {
        Ok((stats, _entries)) => {
            let mut result = stats;
            result.elapsed_ms = start.elapsed().as_millis() as u64;
            result
        }
        Err(e) => {
            eprintln!("Disk usage error: {}", e);
            DiskUsageStats::error(PcaiStatus::IoError)
        }
    }
}

/// FFI: Get disk usage as JSON string with top-N breakdown
///
/// # Safety
/// - `root_path` must be a valid null-terminated UTF-8 string
/// - Caller must free returned string with `pcai_free_string_buffer`
#[no_mangle]
pub unsafe extern "C" fn pcai_get_disk_usage_json(
    root_path: *const c_char,
    top_n: u32,
) -> PcaiStringBuffer {
    if root_path.is_null() {
        return PcaiStringBuffer::error(PcaiStatus::NullPointer);
    }

    let path_str = match CStr::from_ptr(root_path).to_str() {
        Ok(s) => s,
        Err(_) => return PcaiStringBuffer::error(PcaiStatus::InvalidUtf8),
    };

    let start = Instant::now();
    match disk::get_disk_usage(path_str, top_n as usize) {
        Ok((mut stats, entries)) => {
            stats.elapsed_ms = start.elapsed().as_millis() as u64;
            let json_output = disk::DiskUsageJson {
                status: "Success".to_string(),
                root_path: path_str.to_string(),
                total_size_bytes: stats.total_size_bytes,
                total_files: stats.total_files,
                total_dirs: stats.total_dirs,
                elapsed_ms: stats.elapsed_ms,
                top_entries: entries,
            };
            json_to_buffer_pretty(&json_output)
        }
        Err(_) => PcaiStringBuffer::error(PcaiStatus::IoError),
    }
}

/// FFI: Get process statistics
///
/// Returns statistics about running processes on the system.
#[no_mangle]
pub extern "C" fn pcai_get_process_stats() -> ProcessStats {
    let start = Instant::now();
    let stats = process::get_process_stats();
    let mut result = stats;
    result.elapsed_ms = start.elapsed().as_millis() as u64;
    result
}

/// FFI: Get top processes as JSON string sorted by memory/CPU
///
/// # Safety
/// - `sort_by` must be a valid null-terminated UTF-8 string ("memory" or "cpu")
/// - Caller must free returned string with `pcai_free_string_buffer`
#[no_mangle]
pub unsafe extern "C" fn pcai_get_top_processes_json(
    top_n: u32,
    sort_by: *const c_char,
) -> PcaiStringBuffer {
    let sort_key = if sort_by.is_null() {
        "memory"
    } else {
        match CStr::from_ptr(sort_by).to_str() {
            Ok(s) => s,
            Err(_) => "memory",
        }
    };

    let start = Instant::now();
    let (stats, processes) = process::get_top_processes(top_n as usize, sort_key);

    let json_output = process::ProcessListJson {
        status: "Success".to_string(),
        total_processes: stats.total_processes,
        total_threads: stats.total_threads,
        system_cpu_usage: stats.system_cpu_usage,
        system_memory_used_bytes: stats.system_memory_used_bytes,
        system_memory_total_bytes: stats.system_memory_total_bytes,
        elapsed_ms: start.elapsed().as_millis() as u64,
        sort_by: sort_key.to_string(),
        processes,
    };

    json_to_buffer_pretty(&json_output)
}

/// FFI: Get memory usage statistics
#[no_mangle]
pub extern "C" fn pcai_get_memory_stats() -> MemoryStats {
    let start = Instant::now();
    let mut stats = memory::get_memory_stats();
    stats.elapsed_ms = start.elapsed().as_millis() as u64;
    stats
}

/// FFI: Get memory usage as JSON string with detailed breakdown
///
/// # Safety
/// - Caller must free returned string with `pcai_free_string_buffer`
#[no_mangle]
pub extern "C" fn pcai_get_memory_stats_json() -> PcaiStringBuffer {
    let start = Instant::now();
    let stats = memory::get_memory_stats();

    let json_output = memory::MemoryJson {
        status: "Success".to_string(),
        total_memory_bytes: stats.total_memory_bytes,
        used_memory_bytes: stats.used_memory_bytes,
        available_memory_bytes: stats.available_memory_bytes,
        total_swap_bytes: stats.total_swap_bytes,
        used_swap_bytes: stats.used_swap_bytes,
        memory_usage_percent: if stats.total_memory_bytes > 0 {
            (stats.used_memory_bytes as f64 / stats.total_memory_bytes as f64) * 100.0
        } else {
            0.0
        },
        swap_usage_percent: if stats.total_swap_bytes > 0 {
            (stats.used_swap_bytes as f64 / stats.total_swap_bytes as f64) * 100.0
        } else {
            0.0
        },
        elapsed_ms: start.elapsed().as_millis() as u64,
    };

    json_to_buffer_pretty(&json_output)
}

/// FFI: Get performance module version
#[no_mangle]
pub extern "C" fn pcai_performance_version() -> u32 {
    // Version 1.0.0 encoded as 0x010000
    0x010000
}

/// FFI: Test function - returns magic number for verification
#[no_mangle]
pub extern "C" fn pcai_performance_test() -> u32 {
    // Magic number: 0xPERF (letters as hex approximation)
    0x50455246
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        assert_eq!(pcai_performance_version(), 0x010000);
    }

    #[test]
    fn test_magic_number() {
        assert_eq!(pcai_performance_test(), 0x50455246);
    }

    #[test]
    fn test_disk_usage_null_path() {
        unsafe {
            let stats = pcai_get_disk_usage(std::ptr::null(), 10);
            assert_eq!(stats.status, PcaiStatus::NullPointer);
        }
    }

    #[test]
    fn test_process_stats() {
        let stats = pcai_get_process_stats();
        assert_eq!(stats.status, PcaiStatus::Success);
        assert!(stats.total_processes > 0);
    }

    #[test]
    fn test_memory_stats() {
        let stats = pcai_get_memory_stats();
        assert_eq!(stats.status, PcaiStatus::Success);
        assert!(stats.total_memory_bytes > 0);
    }
}
