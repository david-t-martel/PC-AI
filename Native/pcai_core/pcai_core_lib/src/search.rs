//! PCAI Search Module - High-Performance File and Content Operations
//!
//! Provides optimized file traversal and regex search functionality.

use std::os::raw::c_char;
use std::path::Path;
use ignore::WalkBuilder;
use regex::RegexBuilder;
use serde::Serialize;

use crate::string::PcaiStringBuffer;
use crate::PcaiStatus;

#[derive(Serialize)]
pub struct FileMatch {
    pub path: String,
    pub size: u64,
    pub is_readonly: bool,
}

#[derive(Serialize)]
pub struct ContentMatch {
    pub path: String,
    pub line_number: usize,
    pub line: String,
    pub before: Vec<String>,
    pub after: Vec<String>,
}

#[derive(Serialize)]
pub struct SearchResult<T> {
    pub status: String,
    pub pattern: String,
    pub files_scanned: usize,
    pub files_matched: usize,
    pub matches_found: usize,
    pub results: Vec<T>,
    pub elapsed_ms: u64,
}

/// Finds files matching a glob pattern using fast traversal.
pub fn find_files(
    root: &Path,
    pattern: &str,
    max_results: usize,
) -> Result<SearchResult<FileMatch>, PcaiStatus> {
    let start = std::time::Instant::now();
    let glob = globset::Glob::new(pattern).map_err(|_| PcaiStatus::InvalidArgument)?.compile_matcher();

    let mut matches = Vec::new();
    let mut scanned = 0;

    let walker = WalkBuilder::new(root)
        .hidden(false)
        .git_ignore(true)
        .build();

    for entry in walker {
        scanned += 1;
        if let Ok(entry) = entry {
            let entry: ignore::DirEntry = entry;
            if entry.file_type().map_or(false, |ft| ft.is_file()) {
                if glob.is_match(entry.path()) {
                    let metadata = entry.metadata();
                    matches.push(FileMatch {
                        path: entry.path().to_string_lossy().into_owned(),
                        size: metadata.as_ref().map_or(0, |m| m.len()),
                        is_readonly: metadata.as_ref().map_or(false, |m| m.permissions().readonly()),
                    });

                    if max_results > 0 && matches.len() >= max_results {
                        break;
                    }
                }
            }
        }
    }

    Ok(SearchResult {
        status: "Success".to_string(),
        pattern: pattern.to_string(),
        files_scanned: scanned,
        files_matched: matches.len(),
        matches_found: matches.len(),
        results: matches,
        elapsed_ms: start.elapsed().as_millis() as u64,
    })
}

/// Searches file contents using parallel regex matching.
pub fn search_content(
    root: &Path,
    regex_pattern: &str,
    file_pattern: Option<&str>,
    max_results: usize,
    context_lines: usize,
) -> Result<SearchResult<ContentMatch>, PcaiStatus> {
    let start = std::time::Instant::now();
    let re = RegexBuilder::new(regex_pattern)
        .case_insensitive(true)
        .build()
        .map_err(|_| PcaiStatus::InvalidArgument)?;

    let file_glob = file_pattern.map(|p| {
        globset::Glob::new(p).unwrap().compile_matcher()
    });

    let (tx, rx) = std::sync::mpsc::channel();
    let scanned_count = std::sync::atomic::AtomicUsize::new(0);

    let walker = WalkBuilder::new(root)
        .hidden(false)
        .git_ignore(true)
        .threads(rayon::current_num_threads())
        .build_parallel();

    walker.run(|| {
        let tx = tx.clone();
        let re = re.clone();
        let file_glob = file_glob.as_ref();
        let scanned_count = &scanned_count;

        Box::new(move |entry| {
            scanned_count.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
            let entry: ignore::DirEntry = match entry {
                Ok(e) => e,
                Err(_) => return ignore::WalkState::Continue,
            };

            if !entry.file_type().map_or(false, |ft| ft.is_file()) {
                return ignore::WalkState::Continue;
            }

            if let Some(glob) = file_glob {
                if !glob.is_match(entry.path()) {
                    return ignore::WalkState::Continue;
                }
            }

            // Read file and search
            if let Ok(content) = std::fs::read_to_string(entry.path()) {
                let lines: Vec<&str> = content.lines().collect();
                for (idx, line) in lines.iter().enumerate() {
                    if re.is_match(line) {
                        let mut before = Vec::new();
                        let start_ctx = idx.saturating_sub(context_lines);
                        for i in start_ctx..idx {
                            before.push(lines[i].to_string());
                        }

                        let mut after = Vec::new();
                        let end_ctx = std::cmp::min(idx + 1 + context_lines, lines.len());
                        for i in (idx + 1)..end_ctx {
                            after.push(lines[i].to_string());
                        }

                        let m = ContentMatch {
                            path: entry.path().to_string_lossy().into_owned(),
                            line_number: idx + 1,
                            line: line.to_string(),
                            before,
                            after,
                        };

                        if tx.send(m).is_err() {
                            return ignore::WalkState::Quit;
                        }
                    }
                }
            }

            ignore::WalkState::Continue
        })
    });

    drop(tx);
    let mut matches: Vec<ContentMatch> = rx.into_iter().collect();
    let total_matches = matches.len();

    // Count unique files matched
    let mut matched_files = std::collections::HashSet::new();
    for m in &matches {
        matched_files.insert(m.path.clone());
    }
    let files_matched = matched_files.len();

    if max_results > 0 && matches.len() > max_results {
        matches.truncate(max_results);
    }

    Ok(SearchResult {
        status: "Success".to_string(),
        pattern: regex_pattern.to_string(),
        files_scanned: scanned_count.load(std::sync::atomic::Ordering::SeqCst),
        files_matched,
        matches_found: total_matches,
        results: matches,
        elapsed_ms: start.elapsed().as_millis() as u64,
    })
}

// ============================================================================
// FFI Implementation
// ============================================================================

#[no_mangle]
pub extern "C" fn pcai_find_files(
    root_path: *const c_char,
    pattern: *const c_char,
    max_results: u64,
) -> PcaiStringBuffer {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => return PcaiStringBuffer::error(s),
    };

    let pattern_str = match unsafe { crate::string::c_str_to_rust(pattern) } {
        Some(s) => s,
        None => return PcaiStringBuffer::error(PcaiStatus::NullPointer),
    };

    match find_files(&root, pattern_str, max_results as usize) {
        Ok(res) => crate::string::json_to_buffer(&res),
        Err(status) => PcaiStringBuffer::error(status),
    }
}

#[no_mangle]
pub extern "C" fn pcai_search_content(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    max_results: u64,
    context_lines: u32,
) -> PcaiStringBuffer {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => return PcaiStringBuffer::error(s),
    };

    let pattern_str = match unsafe { crate::string::c_str_to_rust(pattern) } {
        Some(s) => s,
        None => return PcaiStringBuffer::error(PcaiStatus::NullPointer),
    };

    let file_pattern_str = unsafe { crate::string::c_str_to_rust(file_pattern) };

    match search_content(
        &root,
        pattern_str,
        file_pattern_str,
        max_results as usize,
        context_lines as usize,
    ) {
        Ok(res) => crate::string::json_to_buffer(&res),
        Err(status) => PcaiStringBuffer::error(status),
    }
}

#[repr(C)]
#[derive(Default)]
pub struct FileSearchStats {
    pub status: PcaiStatus,
    pub files_scanned: u64,
    pub files_matched: u64,
    pub total_size: u64,
    pub elapsed_ms: u64,
}

#[repr(C)]
#[derive(Default)]
pub struct ContentSearchStats {
    pub status: PcaiStatus,
    pub files_scanned: u64,
    pub files_matched: u64,
    pub total_matches: u64,
    pub elapsed_ms: u64,
}

#[no_mangle]
pub extern "C" fn pcai_find_files_stats(
    root_path: *const c_char,
    pattern: *const c_char,
    max_results: u64,
) -> FileSearchStats {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => return FileSearchStats { status: s, ..Default::default() },
    };

    let pattern_str = match unsafe { crate::string::c_str_to_rust(pattern) } {
        Some(s) => s,
        None => return FileSearchStats { status: PcaiStatus::NullPointer, ..Default::default() },
    };

    match find_files(&root, pattern_str, max_results as usize) {
        Ok(res) => FileSearchStats {
            status: PcaiStatus::Success,
            files_scanned: res.files_scanned as u64,
            files_matched: res.matches_found as u64,
            total_size: 0,
            elapsed_ms: res.elapsed_ms,
        },
        Err(status) => FileSearchStats { status, ..Default::default() },
    }
}

#[no_mangle]
pub extern "C" fn pcai_search_content_stats(
    root_path: *const c_char,
    pattern: *const c_char,
    file_pattern: *const c_char,
    max_results: u64,
) -> ContentSearchStats {
    let root = match crate::path::parse_path_ffi(root_path) {
        Ok(p) => p,
        Err(s) => return ContentSearchStats { status: s, ..Default::default() },
    };

    let pattern_str = match unsafe { crate::string::c_str_to_rust(pattern) } {
        Some(s) => s,
        None => return ContentSearchStats { status: PcaiStatus::NullPointer, ..Default::default() },
    };

    let file_pattern_str = unsafe { crate::string::c_str_to_rust(file_pattern) };

    match search_content(&root, pattern_str, file_pattern_str, max_results as usize, 0) {
        Ok(res) => ContentSearchStats {
            status: PcaiStatus::Success,
            files_scanned: res.files_scanned as u64,
            files_matched: res.files_matched as u64,
            total_matches: res.matches_found as u64,
            elapsed_ms: res.elapsed_ms,
        },
        Err(status) => ContentSearchStats { status, ..Default::default() },
    }
}
