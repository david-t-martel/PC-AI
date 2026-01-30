//! mistral.rs backend implementation

use async_trait::async_trait;

use super::{FinishReason, GenerateRequest, GenerateResponse, InferenceBackend};
use crate::{Error, Result};

pub struct MistralRsBackend {
    model: Option<()>, // TODO: Replace with actual mistralrs types
}

impl MistralRsBackend {
    pub fn new() -> Self {
        Self { model: None }
    }
}

impl Default for MistralRsBackend {
    fn default() -> Self {
        Self::new()
    }
}

#[async_trait]
impl InferenceBackend for MistralRsBackend {
    async fn load_model(&mut self, _model_path: &str) -> Result<()> {
        // TODO: Implement mistral.rs model loading
        tracing::warn!("MistralRsBackend::load_model not yet implemented");
        Err(Error::Backend("Not implemented".to_string()))
    }

    async fn generate(&self, request: GenerateRequest) -> Result<GenerateResponse> {
        // TODO: Implement mistral.rs generation
        tracing::warn!("MistralRsBackend::generate not yet implemented");
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
        "mistral.rs"
    }
}
