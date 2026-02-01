//! FFI integration tests for pcai-inference
//!
//! This file runs the FFI boundary tests defined in the ffi/ subdirectory.
//! Tests verify:
//! - Memory safety across FFI boundary
//! - Concurrent access patterns
//! - Error propagation
//!
//! ## Running Tests
//!
//! ```bash
//! # Run all FFI tests (requires ffi feature)
//! cargo test --features ffi --test ffi_tests
//!
//! # Run with llamacpp backend
//! cargo test --features "ffi,llamacpp" --test ffi_tests
//! ```

#[cfg(feature = "ffi")]
mod ffi;
