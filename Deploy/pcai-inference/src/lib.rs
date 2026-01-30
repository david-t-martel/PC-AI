//! # pcai-inference
//!
//! Dual-backend LLM inference engine for PC diagnostics.
//!
//! Supports two backends:
//! - llama.cpp via llama-cpp-2 (feature: `llamacpp`)
//! - mistral.rs (feature: `mistralrs-backend`)
//!
//! Optional features:
//! - `cuda`: Enable GPU acceleration
//! - `server`: HTTP server with Axum
//! - `ffi`: C FFI exports for PowerShell integration

pub mod backends;
pub mod config;

#[cfg(feature = "server")]
pub mod http;

#[cfg(feature = "ffi")]
pub mod ffi;

pub use backends::InferenceBackend;
pub use config::InferenceConfig;

/// Result type for inference operations
pub type Result<T> = std::result::Result<T, Error>;

/// Error types for inference operations
#[derive(Debug, thiserror::Error)]
pub enum Error {
    #[error("Backend error: {0}")]
    Backend(String),

    #[error("Configuration error: {0}")]
    Config(String),

    #[error("Model not loaded")]
    ModelNotLoaded,

    #[error("Invalid input: {0}")]
    InvalidInput(String),

    #[error("IO error: {0}")]
    Io(#[from] std::io::Error),

    #[error("Serialization error: {0}")]
    Serialization(#[from] serde_json::Error),

    #[error(transparent)]
    Other(#[from] anyhow::Error),
}

// Candle error conversion for mistral.rs backend
// Note: candle_core::Error is not directly accessible, but we can convert via anyhow
// which is already implemented in the Other variant
