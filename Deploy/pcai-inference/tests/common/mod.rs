//! Shared test utilities for pcai-inference integration tests
//!
//! This module provides common functionality used across multiple test files.

use std::path::PathBuf;

/// Find a test GGUF model in common locations
///
/// Searches in order:
/// 1. PCAI_TEST_MODEL environment variable
/// 2. Ollama cache (~/.ollama/models/blobs)
/// 3. LM Studio cache (~/.cache/lm-studio/models)
/// 4. Windows LOCALAPPDATA\lm-studio\models
///
/// Returns the first GGUF file found, or None if no model is available.
pub fn find_test_model() -> Option<PathBuf> {
    // Check environment variable first
    if let Ok(path) = std::env::var("PCAI_TEST_MODEL") {
        let path_buf = PathBuf::from(&path);
        if path_buf.exists() {
            return Some(path_buf);
        }
    }

    // Check Ollama cache (Linux/Mac)
    if let Ok(home) = std::env::var("HOME") {
        let ollama_path = PathBuf::from(home).join(".ollama/models/blobs");
        if let Some(model) = find_gguf_in_dir(&ollama_path) {
            return Some(model);
        }

        // Check LM Studio cache (Linux/Mac)
        let lm_studio_path = PathBuf::from(std::env::var("HOME").unwrap())
            .join(".cache/lm-studio/models");
        if let Some(model) = find_gguf_in_dir(&lm_studio_path) {
            return Some(model);
        }
    }

    // Check LM Studio cache (Windows)
    if let Ok(localappdata) = std::env::var("LOCALAPPDATA") {
        let lm_studio_path = PathBuf::from(localappdata).join("lm-studio\\models");
        if let Some(model) = find_gguf_in_dir(&lm_studio_path) {
            return Some(model);
        }
    }

    None
}

/// Find the first .gguf file in a directory (recursive)
fn find_gguf_in_dir(dir: &PathBuf) -> Option<PathBuf> {
    if !dir.exists() || !dir.is_dir() {
        return None;
    }

    // Try direct children first
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let path = entry.path();

            // If it's a GGUF file, return it
            if path.is_file() && path.extension().and_then(|s| s.to_str()) == Some("gguf") {
                return Some(path);
            }

            // If it's a directory, search recursively (limit depth to avoid deep scans)
            if path.is_dir() {
                if let Some(model) = find_gguf_in_dir(&path) {
                    return Some(model);
                }
            }
        }
    }

    None
}

/// Get the model path from environment or panic with helpful message
///
/// Use this in tests that require a real model file.
pub fn require_test_model() -> PathBuf {
    find_test_model().unwrap_or_else(|| {
        panic!(
            "No test model found. Set PCAI_TEST_MODEL environment variable to a .gguf file path, \
             or install a model via Ollama/LM Studio."
        )
    })
}

/// Check if a test model is available
pub fn has_test_model() -> bool {
    find_test_model().is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_find_test_model_respects_env() {
        // If PCAI_TEST_MODEL is set and valid, it should be found
        if let Ok(path) = std::env::var("PCAI_TEST_MODEL") {
            let path_buf = PathBuf::from(&path);
            if path_buf.exists() {
                let found = find_test_model();
                assert!(found.is_some());
                assert_eq!(found.unwrap(), path_buf);
            }
        }
    }

    #[test]
    fn test_has_test_model() {
        // This should not panic
        let _ = has_test_model();
    }
}
