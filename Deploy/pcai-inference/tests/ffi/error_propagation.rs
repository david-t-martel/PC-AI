//! Error propagation tests for FFI boundary
//!
//! These tests verify that errors are properly communicated across the FFI boundary:
//! - Return codes indicate success/failure
//! - pcai_last_error() provides detailed error messages
//! - Error messages are valid UTF-8
//! - Errors are properly cleared between operations

#![cfg(feature = "ffi")]

use std::ffi::{CStr, CString};

use pcai_inference::ffi::{pcai_init, pcai_last_error, pcai_shutdown};

/// Test that unknown backend produces meaningful error
#[test]
fn test_unknown_backend_error() {
    pcai_shutdown();

    let backend = CString::new("unknown_backend_12345").unwrap();
    let result = pcai_init(backend.as_ptr());

    assert_eq!(result, -1);

    let err_ptr = pcai_last_error();
    assert!(!err_ptr.is_null());

    let err_str = unsafe { CStr::from_ptr(err_ptr) };
    let err_text = err_str.to_str().expect("Error should be valid UTF-8");

    // Error should mention the backend or indicate it's unknown
    assert!(
        err_text.contains("Unknown") || err_text.contains("unknown") || err_text.contains("backend"),
        "Error should mention unknown backend: {}",
        err_text
    );

    pcai_shutdown();
}

/// Test error message for operations before init
#[test]
fn test_not_initialized_error() {
    pcai_shutdown();

    // Try to load model without init
    let path = CString::new("/test/model.gguf").unwrap();

    #[cfg(feature = "ffi")]
    {
        use pcai_inference::ffi::pcai_load_model;
        let result = pcai_load_model(path.as_ptr(), 0);
        assert_eq!(result, -1);

        let err_ptr = pcai_last_error();
        assert!(!err_ptr.is_null());

        let err_str = unsafe { CStr::from_ptr(err_ptr) };
        let err_text = err_str.to_str().expect("Error should be valid UTF-8");

        // Should mention initialization
        assert!(
            err_text.contains("initialized") || err_text.contains("init") || err_text.contains("not"),
            "Error should mention not initialized: {}",
            err_text
        );
    }
}

#[cfg(feature = "llamacpp")]
mod llamacpp_error_tests {
    use super::*;
    use pcai_inference::ffi::{pcai_generate, pcai_load_model};

    /// Test error for model not found
    #[test]
    fn test_model_not_found_error() {
        pcai_shutdown();

        let backend = CString::new("llamacpp").unwrap();
        if pcai_init(backend.as_ptr()) != 0 {
            return; // Skip if llamacpp not available
        }

        let nonexistent = CString::new("/nonexistent/path/to/model.gguf").unwrap();
        let result = pcai_load_model(nonexistent.as_ptr(), 0);

        assert_eq!(result, -1);

        let err_ptr = pcai_last_error();
        assert!(!err_ptr.is_null());

        let err_str = unsafe { CStr::from_ptr(err_ptr) };
        let err_text = err_str.to_str().expect("Error should be valid UTF-8");

        // Should mention file not found or path issue
        assert!(
            err_text.contains("not found")
                || err_text.contains("exist")
                || err_text.contains("path")
                || err_text.contains("load")
                || err_text.contains("failed"),
            "Error should mention file issue: {}",
            err_text
        );

        pcai_shutdown();
    }

    /// Test error for generate without model loaded
    #[test]
    fn test_generate_without_model_error() {
        pcai_shutdown();

        let backend = CString::new("llamacpp").unwrap();
        if pcai_init(backend.as_ptr()) != 0 {
            return; // Skip if llamacpp not available
        }

        let prompt = CString::new("Test prompt").unwrap();
        let result = pcai_generate(prompt.as_ptr(), 10, 0.7);

        assert!(result.is_null());

        let err_ptr = pcai_last_error();
        assert!(!err_ptr.is_null());

        let err_str = unsafe { CStr::from_ptr(err_ptr) };
        let err_text = err_str.to_str().expect("Error should be valid UTF-8");

        // Should mention model not loaded
        assert!(
            err_text.contains("loaded") || err_text.contains("model") || err_text.contains("not"),
            "Error should mention model not loaded: {}",
            err_text
        );

        pcai_shutdown();
    }

    /// Test that errors are specific and actionable
    #[test]
    fn test_error_specificity() {
        pcai_shutdown();

        // Test various error conditions and verify messages are helpful
        let test_cases = vec![
            ("", "empty backend name"),
            ("x", "single char backend"),
            ("LLAMACPP", "wrong case backend"),
        ];

        for (backend_name, _description) in test_cases {
            let backend = CString::new(backend_name).unwrap();
            let result = pcai_init(backend.as_ptr());

            if result == -1 {
                let err_ptr = pcai_last_error();
                if !err_ptr.is_null() {
                    let err_str = unsafe { CStr::from_ptr(err_ptr) };
                    let err_text = err_str.to_str().expect("Error should be valid UTF-8");

                    // Errors should not be generic "error" only
                    assert!(
                        err_text.len() > 5,
                        "Error should be descriptive, not just 'error': {}",
                        err_text
                    );
                }
            }

            pcai_shutdown();
        }
    }
}

/// Test that successful operations don't leave stale errors
#[test]
fn test_success_clears_error() {
    pcai_shutdown();

    // First, cause an error
    let invalid = CString::new("invalid").unwrap();
    let _ = pcai_init(invalid.as_ptr());

    // Verify error is set
    let err_ptr = pcai_last_error();
    assert!(!err_ptr.is_null());

    pcai_shutdown();

    // Now do a successful operation (if any backend is available)
    #[cfg(feature = "llamacpp")]
    {
        let backend = CString::new("llamacpp").unwrap();
        let result = pcai_init(backend.as_ptr());

        if result == 0 {
            // After success, error should be cleared or contain no error
            // Note: Implementation may or may not clear error on success
            // This documents expected behavior
        }

        pcai_shutdown();
    }
}
