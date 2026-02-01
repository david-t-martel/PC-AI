//! Configuration types for inference engine

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Configuration for the inference engine
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct InferenceConfig {
    /// Backend to use
    pub backend: BackendConfig,

    /// Model configuration
    pub model: ModelConfig,

    /// Server configuration (if feature = "server")
    #[cfg(feature = "server")]
    pub server: Option<ServerConfig>,
}

/// Backend selection
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BackendConfig {
    #[cfg(feature = "llamacpp")]
    LlamaCpp {
        #[serde(default)]
        n_gpu_layers: Option<i32>,
        #[serde(default)]
        n_ctx: Option<usize>,
    },

    #[cfg(feature = "mistralrs-backend")]
    MistralRs {
        #[serde(default)]
        device: Option<String>,
    },
}

/// Model configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    /// Path to model file
    pub path: PathBuf,

    /// Model type hint (optional)
    pub model_type: Option<String>,

    /// Default generation parameters
    #[serde(default)]
    pub generation: GenerationDefaults,
}

/// Default generation parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GenerationDefaults {
    #[serde(default = "default_max_tokens")]
    pub max_tokens: usize,

    #[serde(default = "default_temperature")]
    pub temperature: f32,

    #[serde(default = "default_top_p")]
    pub top_p: f32,

    #[serde(default)]
    pub stop: Vec<String>,
}

impl Default for GenerationDefaults {
    fn default() -> Self {
        Self {
            max_tokens: default_max_tokens(),
            temperature: default_temperature(),
            top_p: default_top_p(),
            stop: vec![],
        }
    }
}

fn default_max_tokens() -> usize {
    512
}

fn default_temperature() -> f32 {
    0.7
}

fn default_top_p() -> f32 {
    0.95
}

/// Server configuration
#[cfg(feature = "server")]
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ServerConfig {
    /// Host to bind to
    #[serde(default = "default_host")]
    pub host: String,

    /// Port to bind to
    #[serde(default = "default_port")]
    pub port: u16,

    /// Enable CORS
    #[serde(default = "default_cors")]
    pub cors: bool,
}

#[cfg(feature = "server")]
fn default_host() -> String {
    "127.0.0.1".to_string()
}

#[cfg(feature = "server")]
fn default_port() -> u16 {
    8080
}

#[cfg(feature = "server")]
fn default_cors() -> bool {
    true
}

#[cfg(feature = "server")]
impl Default for ServerConfig {
    fn default() -> Self {
        Self {
            host: default_host(),
            port: default_port(),
            cors: default_cors(),
        }
    }
}

impl InferenceConfig {
    /// Load configuration from a file
    pub fn from_file(path: impl AsRef<std::path::Path>) -> crate::Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Self = serde_json::from_str(&content)?;
        Ok(config)
    }

    /// Save configuration to a file
    pub fn to_file(&self, path: impl AsRef<std::path::Path>) -> crate::Result<()> {
        let content = serde_json::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}
