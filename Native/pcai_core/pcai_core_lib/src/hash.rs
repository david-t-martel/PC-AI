//! PCAI Hash Module - Parallel Duplicate Detection
//!
//! Provides optimized multi-phase duplicate detection using SHA-256.

use std::collections::HashMap;
use std::os::raw::c_char;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use ignore::WalkBuilder;
use rayon::prelude::*;
use serde::Serialize;
use sha2::{Digest, Sha256};

use crate::PcaiStatus;
use crate::string::PcaiStringBuffer;

#[derive(Serialize)]
pub struct DuplicateGroup {
    pub hash: String,
    pub size: u64,
    pub paths: Vec<String>,
    pub wasted_bytes: u64,
}

#[derive(Serialize)]
pub struct DuplicateResult {
    pub status: String,
    pub files_scanned: usize,
    pub duplicate_groups: usize,
    pub duplicate_files: usize,
    pub wasted_bytes: u64,
    pub results: Vec<DuplicateGroup>,
    pub elapsed_ms: u64,
}

/// Finds duplicate files in a directory using a multi-phase parallel approach.
pub fn find_duplicates(
    root: &Path,
    min_size: u64,
    include_pattern: Option<&str>,
    exclude_pattern: Option<&str>,
) -> Result<DuplicateResult, PcaiStatus> {
    let start = std::time::Instant::now();

    // Compile matchers
    let include_matcher =
        include_pattern.and_then(|p| globset::Glob::new(p).ok().map(|g| g.compile_matcher()));
    let exclude_matcher =
        exclude_pattern.and_then(|p| globset::Glob::new(p).ok().map(|g| g.compile_matcher()));

    // Phase 1: Fast enumeration and size grouping
    let mut size_map: HashMap<u64, Vec<PathBuf>> = HashMap::new();
    let mut scanned = 0;

    let walker = WalkBuilder::new(root)
        .hidden(false)
        .git_ignore(true)
        .build();

    for entry in walker {
        scanned += 1;
        if let Ok(entry) = entry {
            if entry.file_type().map_or(false, |ft| ft.is_file()) {
                let metadata = match entry.metadata() {
                    Ok(m) => m,
                    Err(_) => continue,
                };

                let path = entry.path();
                let size = metadata.len();

                if size >= min_size {
                    // Apply patterns
                    if let Some(ref matcher) = include_matcher {
                        if !matcher.is_match(path) {
                            continue;
                        }
                    }
                    if let Some(ref matcher) = exclude_matcher {
                        if matcher.is_match(path) {
                            continue;
                        }
                    }

                    size_map.entry(size).or_default().push(path.to_path_buf());
                }
            }
        }
    }

    // Phase 2: Parallel hashing of candidates (only for sizes with multiple files)
    let candidates: Vec<(u64, Vec<PathBuf>)> = size_map
        .into_iter()
        .filter(|(_, paths)| paths.len() > 1)
        .collect();

    let hash_groups: Arc<Mutex<HashMap<(u64, String), Vec<String>>>> =
        Arc::new(Mutex::new(HashMap::new()));

    candidates.into_par_iter().for_each(|(size, paths)| {
        paths.into_par_iter().for_each(|path| {
            if let Ok(hash) = compute_file_hash(&path) {
                if let Ok(mut groups) = hash_groups.lock() {
                    groups
                        .entry((size, hash))
                        .or_default()
                        .push(path.to_string_lossy().into_owned());
                }
            }
        });
    });

    // Phase 3: Final aggregation
    let groups = match Arc::try_unwrap(hash_groups) {
        Ok(m) => m.into_inner().unwrap_or_default(),
        Err(_) => return Err(PcaiStatus::InternalError),
    };
    let mut results = Vec::new();
    let mut total_wasted = 0;
    let mut total_dups = 0;

    for ((size, hash), paths) in groups {
        if paths.len() > 1 {
            let wasted = size * (paths.len() - 1) as u64;
            total_wasted += wasted;
            total_dups += paths.len() - 1;

            results.push(DuplicateGroup {
                hash,
                size,
                paths,
                wasted_bytes: wasted,
            });
        }
    }

    // Sort by wasted bytes descending
    results.sort_by(|a, b| b.wasted_bytes.cmp(&a.wasted_bytes));

    Ok(DuplicateResult {
        status: "Success".to_string(),
        files_scanned: scanned,
        duplicate_groups: results.len(),
        duplicate_files: total_dups,
        wasted_bytes: total_wasted,
        results,
        elapsed_ms: start.elapsed().as_millis() as u64,
    })
}

fn compute_file_hash(path: &Path) -> std::io::Result<String> {
    let mut file = std::fs::File::open(path)?;
    let mut hasher = Sha256::new();
    std::io::copy(&mut file, &mut hasher)?;
    Ok(format!("{:x}", hasher.finalize()))
}

// ============================================================================
// FFI Implementation
// ============================================================================

#[no_mangle]
pub extern "C" fn pcai_find_duplicates(
    root_path: *const c_char,
    min_size: u64,
    include_pattern: *const c_char,
    exclude_pattern: *const c_char,
) -> PcaiStringBuffer {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => return PcaiStringBuffer::error(s),
    };

    let include_str = unsafe { crate::string::c_str_to_rust(include_pattern) };
    let exclude_str = unsafe { crate::string::c_str_to_rust(exclude_pattern) };

    match find_duplicates(&root, min_size, include_str, exclude_str) {
        Ok(res) => crate::string::json_to_buffer(&res),
        Err(status) => PcaiStringBuffer::error(status),
    }
}

#[repr(C)]
#[derive(Default)]
pub struct DuplicateStats {
    pub status: PcaiStatus,
    pub files_scanned: u64,
    pub duplicate_groups: u64,
    pub duplicate_files: u64,
    pub wasted_bytes: u64,
    pub elapsed_ms: u64,
}

#[no_mangle]
pub extern "C" fn pcai_find_duplicates_stats(
    root_path: *const c_char,
    min_size: u64,
    include_pattern: *const c_char,
    exclude_pattern: *const c_char,
) -> DuplicateStats {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => {
            return DuplicateStats {
                status: s,
                ..Default::default()
            };
        }
    };

    let include_str = unsafe { crate::string::c_str_to_rust(include_pattern) };
    let exclude_str = unsafe { crate::string::c_str_to_rust(exclude_pattern) };

    match find_duplicates(&root, min_size, include_str, exclude_str) {
        Ok(res) => DuplicateStats {
            status: PcaiStatus::Success,
            files_scanned: res.files_scanned as u64,
            duplicate_groups: res.duplicate_groups as u64,
            duplicate_files: res.duplicate_files as u64,
            wasted_bytes: res.wasted_bytes,
            elapsed_ms: res.elapsed_ms,
        },
        Err(status) => DuplicateStats {
            status,
            ..Default::default()
        },
    }
}
