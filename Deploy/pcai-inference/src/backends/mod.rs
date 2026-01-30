//! Inference backend implementations

use async_trait::async_trait;
use serde::{Deserialize, Serialize};

use crate::{Error, Result};

#[cfg(feature = "llamacpp")]
pub mod llamacpp;

#[cfg(feature = "mistralrs-backend")]
pub mod mistralrs;

/// Request for text generation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerateRequest {
    pub prompt: String,
    #[serde(default)]
    pub max_tokens: Option<usize>,
    #[serde(default)]
    pub temperature: Option<f32>,
    #[serde(default)]
    pub top_p: Option<f32>,
    #[serde(default)]
    pub stop: Vec<String>,
}

/// Response from text generation
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerateResponse {
    pub text: String,
    pub tokens_generated: usize,
    pub finish_reason: FinishReason,
}

/// Reason for generation completion
#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinishReason {
    Stop,
    Length,
    Error,
}

/// Trait for inference backends
#[async_trait]
pub trait InferenceBackend: Send + Sync {
    /// Load a model from the given path
    async fn load_model(&mut self, model_path: &str) -> Result<()>;

    /// Generate text from a prompt
    async fn generate(&self, request: GenerateRequest) -> Result<GenerateResponse>;

    /// Unload the current model
    async fn unload_model(&mut self) -> Result<()>;

    /// Check if a model is loaded
    fn is_loaded(&self) -> bool;

    /// Get backend name
    fn backend_name(&self) -> &'static str;
}

/// Factory for creating backends
pub enum BackendType {
    #[cfg(feature = "llamacpp")]
    LlamaCpp,

    #[cfg(feature = "mistralrs-backend")]
    MistralRs,
}

impl BackendType {
    pub fn create(&self) -> Result<Box<dyn InferenceBackend>> {
        match self {
            #[cfg(feature = "llamacpp")]
            BackendType::LlamaCpp => Ok(Box::new(llamacpp::LlamaCppBackend::new())),

            #[cfg(feature = "mistralrs-backend")]
            BackendType::MistralRs => Ok(Box::new(mistralrs::MistralRsBackend::new())),

            #[allow(unreachable_patterns)]
            _ => Err(Error::Backend("No backend feature enabled".to_string())),
        }
    }
}
