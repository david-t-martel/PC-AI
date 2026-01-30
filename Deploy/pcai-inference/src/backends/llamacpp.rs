//! llama.cpp backend implementation

use async_trait::async_trait;

use super::{FinishReason, GenerateRequest, GenerateResponse, InferenceBackend};
use crate::{Error, Result};

pub struct LlamaCppBackend {
    model: Option<()>, // TODO: Replace with actual llama_cpp_2 types
}

impl LlamaCppBackend {
    pub fn new() -> Self {
        Self { model: None }
    }
}

impl Default for LlamaCppBackend {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl InferenceBackend for LlamaCppBackend {
    async fn load_model(&mut self, _model_path: &str) -> Result<()> {
        // TODO: Implement llama.cpp model loading
        tracing::warn!("LlamaCppBackend::load_model not yet implemented");
        Err(Error::Backend("Not implemented".to_string()))
    }

    async fn generate(&self, request: GenerateRequest) -> Result<GenerateResponse> {
        // TODO: Implement llama.cpp generation
        tracing::warn!("LlamaCppBackend::generate not yet implemented");
        let _ = request;
        Err(Error::Backend("Not implemented".to_string()))
    }

    async fn unload_model(&mut self) -> Result<()> {
        self.model = None;
        Ok(())
    }

    fn is_loaded(&self) -> bool {
        self.model.is_some()
    }

    fn backend_name(&self) -> &'static str {
        "llama.cpp"
    }
}
