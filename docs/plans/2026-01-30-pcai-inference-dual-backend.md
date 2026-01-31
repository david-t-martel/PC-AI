# PCAI-Inference Dual-Backend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Status:** ✅ Complete (pcai-inference crate, HTTP server, FFI exports, dual backends, tests, and build scripts are present)

**Goal:** Build a native Rust LLM inference engine with dual backends (llama_cpp-rs + mistralrs) supporting GPU acceleration, OpenAI-compatible HTTP API, and PowerShell FFI—replacing the current vLLM/Ollama/Docker dependency.

**Architecture:** Feature-flagged dual-backend design with a shared `InferenceBackend` trait. llama_cpp-rs provides broadest GGUF compatibility for Ollama/LM Studio models; mistralrs adds multimodal support when available. HTTP server reuses patterns from existing `rust-functiongemma-runtime`. FFI exports enable direct PowerShell calls for low-latency paths.

**Tech Stack:**
- `llama-cpp-2` (GGUF inference, CUDA)
- `mistralrs` (multimodal, Candle-based)
- `axum` + `tokio` (HTTP server)
- Existing OpenAI API structs from `rust-functiongemma-runtime`

**Parallel Execution:** Tasks 1-3 are sequential (scaffolding). Tasks 4-5 can run in parallel (separate backends). Tasks 6-8 depend on backends completing.

---

## Task 1: Project Scaffolding

**Files:**
- Create: `Deploy/pcai-inference/Cargo.toml`
- Create: `Deploy/pcai-inference/src/lib.rs`
- Create: `Deploy/pcai-inference/src/main.rs`
- Create: `Deploy/pcai-inference/build.rs`
- Modify: `Deploy/Cargo.toml` (if workspace exists)

**Step 1: Create directory structure**

```powershell
New-Item -ItemType Directory -Path "C:\Users\david\PC_AI\Deploy\pcai-inference\src\backends" -Force
New-Item -ItemType Directory -Path "C:\Users\david\PC_AI\Deploy\pcai-inference\src\http" -Force
New-Item -ItemType Directory -Path "C:\Users\david\PC_AI\Deploy\pcai-inference\src\ffi" -Force
New-Item -ItemType Directory -Path "C:\Users\david\PC_AI\Deploy\pcai-inference\tests" -Force
```

**Step 2: Create Cargo.toml with feature flags**

```toml
[package]
name = "pcai-inference"
version = "0.1.0"
edition = "2021"
description = "Native Rust LLM inference with dual backends for PC_AI"

[lib]
crate-type = ["cdylib", "rlib"]

[[bin]]
name = "pcai-inference-server"
path = "src/main.rs"
required-features = ["server"]

[features]
default = ["llamacpp", "server"]

# Backends
llamacpp = ["dep:llama-cpp-2"]
mistralrs-backend = ["dep:mistralrs"]

# GPU acceleration
cuda = ["llama-cpp-2?/cuda"]

# Build targets
server = ["dep:axum", "dep:tower-http"]
ffi = []

[dependencies]
# Core
anyhow = "1.0"
thiserror = "1.0"
tokio = { version = "1", features = ["rt-multi-thread", "macros", "sync"] }
serde = { version = "1", features = ["derive"] }
serde_json = "1"
tracing = "0.1"
tracing-subscriber = { version = "0.3", features = ["env-filter"] }
async-trait = "0.1"

# HTTP server (optional)
axum = { version = "0.7", optional = true }
tower-http = { version = "0.5", features = ["cors", "trace"], optional = true }

# Backends (optional)
llama-cpp-2 = { version = "0.1", optional = true }
mistralrs = { version = "0.3", optional = true }

[build-dependencies]
cc = "1.0"

[dev-dependencies]
reqwest = { version = "0.12", features = ["json"] }
tempfile = "3"
```

**Step 3: Create stub lib.rs**

```rust
//! PCAI-Inference: Dual-backend LLM inference engine
//!
//! Supports llama_cpp-rs (GGUF) and mistralrs backends with
//! automatic GPU detection and model routing.

pub mod backends;
pub mod config;

#[cfg(feature = "server")]
pub mod http;

#[cfg(feature = "ffi")]
pub mod ffi;

pub use backends::{Backend, InferenceBackend};
pub use config::{GpuConfig, ModelConfig};
```

**Step 4: Create stub main.rs**

```rust
//! PCAI-Inference HTTP Server
//!
//! OpenAI-compatible API server with dual-backend support.

use pcai_inference::http;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    tracing::info!("Starting PCAI-Inference server...");
    http::run_server().await
}
```

**Step 5: Create build.rs for CUDA detection**

```rust
//! Build script for CUDA detection and backend configuration

fn main() {
    // Detect CUDA availability
    if std::env::var("CUDA_PATH").is_ok() {
        println!("cargo:rustc-cfg=has_cuda");
        println!("cargo:warning=CUDA detected, enabling GPU acceleration");
    }

    // Emit backend configuration
    #[cfg(feature = "llamacpp")]
    println!("cargo:rustc-cfg=backend_llamacpp");

    #[cfg(feature = "mistralrs-backend")]
    println!("cargo:rustc-cfg=backend_mistralrs");
}
```

**Step 6: Verify project compiles**

```powershell
cd C:\Users\david\PC_AI\Deploy\pcai-inference
cargo check --no-default-features
```

Expected: Compilation succeeds (no backends enabled yet)

**Step 7: Commit scaffolding**

```powershell
git add Deploy/pcai-inference/
git commit -m "feat(pcai-inference): scaffold dual-backend inference crate"
```

---

## Task 2: Backend Trait & Config Types

**Files:**
- Create: `Deploy/pcai-inference/src/backends/mod.rs`
- Create: `Deploy/pcai-inference/src/config.rs`

**Step 1: Define backend trait**

Create `src/backends/mod.rs`:

```rust
//! Backend trait and implementations for LLM inference

use async_trait::async_trait;
use serde::{Deserialize, Serialize};
use std::path::Path;

#[cfg(feature = "llamacpp")]
pub mod llamacpp;

#[cfg(feature = "mistralrs-backend")]
pub mod mistralrs;

/// Chat message for inference
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ChatMessage {
    pub role: String,
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<serde_json::Value>,
}

/// Generation parameters
#[derive(Debug, Clone, Default)]
pub struct GenerateParams {
    pub temperature: f32,
    pub top_p: f32,
    pub top_k: u32,
    pub max_tokens: u32,
    pub stop_sequences: Vec<String>,
    pub seed: Option<u64>,
}

/// Response from inference
#[derive(Debug, Clone, Serialize)]
pub struct ChatResponse {
    pub content: Option<String>,
    pub tool_calls: Option<serde_json::Value>,
    pub finish_reason: FinishReason,
    pub tokens_generated: u32,
}

#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum FinishReason {
    Stop,
    Length,
    ToolCalls,
}

/// Model information
#[derive(Debug, Clone, Serialize)]
pub struct ModelInfo {
    pub id: String,
    pub backend: Backend,
    pub architecture: String,
    pub quantization: Option<String>,
    pub context_length: u32,
}

/// Available backends
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Backend {
    LlamaCpp,
    MistralRs,
}

/// Backend capabilities
#[derive(Debug, Clone)]
pub struct BackendCapabilities {
    pub supports_gpu: bool,
    pub supports_streaming: bool,
    pub supports_tool_calls: bool,
    pub supports_vision: bool,
    pub max_context_length: u32,
}

/// Core inference trait implemented by all backends
#[async_trait]
pub trait InferenceBackend: Send + Sync {
    /// Load a model from the given path
    async fn load_model(&mut self, model_path: &Path, config: &crate::config::ModelConfig) -> anyhow::Result<()>;

    /// Unload the current model
    async fn unload_model(&mut self) -> anyhow::Result<()>;

    /// Check if a model is loaded
    fn is_loaded(&self) -> bool;

    /// Generate a response (non-streaming)
    async fn generate(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
    ) -> anyhow::Result<ChatResponse>;

    /// Generate with streaming callback
    async fn generate_streaming(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
        on_token: Box<dyn FnMut(&str) + Send>,
    ) -> anyhow::Result<ChatResponse>;

    /// List available/loaded models
    fn list_models(&self) -> Vec<ModelInfo>;

    /// Get backend capabilities
    fn capabilities(&self) -> BackendCapabilities;

    /// Get backend identifier
    fn backend_type(&self) -> Backend;
}

/// Create backend instance based on feature flags and availability
pub fn create_backend(preferred: Option<Backend>) -> anyhow::Result<Box<dyn InferenceBackend>> {
    match preferred {
        #[cfg(feature = "llamacpp")]
        Some(Backend::LlamaCpp) | None => {
            Ok(Box::new(llamacpp::LlamaCppBackend::new()?))
        }
        #[cfg(feature = "mistralrs-backend")]
        Some(Backend::MistralRs) => {
            Ok(Box::new(mistralrs::MistralRsBackend::new()?))
        }
        #[allow(unreachable_patterns)]
        _ => anyhow::bail!("Requested backend not available (check feature flags)"),
    }
}
```

**Step 2: Define config types**

Create `src/config.rs`:

```rust
//! Configuration types for model loading and GPU detection

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// GPU configuration detected at runtime
#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum GpuConfig {
    /// No GPU available, CPU-only inference
    CpuOnly,
    /// Single GPU available
    SingleGpu { device_id: u32, name: String, vram_mb: u64 },
    /// Multiple GPUs available for tensor parallelism
    MultiGpu { devices: Vec<GpuDevice> },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GpuDevice {
    pub device_id: u32,
    pub name: String,
    pub vram_mb: u64,
    /// Fraction of model layers to assign (0.0-1.0)
    pub layer_fraction: f32,
}

/// Model loading configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModelConfig {
    /// Path to GGUF or safetensors model
    pub model_path: PathBuf,

    /// Override context length (None = use model default)
    pub context_length: Option<u32>,

    /// Number of layers to offload to GPU (-1 = all)
    pub gpu_layers: i32,

    /// Specific GPU devices to use
    pub gpu_devices: Option<Vec<u32>>,

    /// Chat template override
    pub chat_template: Option<String>,

    /// Batch size for prompt processing
    pub batch_size: u32,
}

impl Default for ModelConfig {
    fn default() -> Self {
        Self {
            model_path: PathBuf::new(),
            context_length: None,
            gpu_layers: -1, // All layers to GPU
            gpu_devices: None,
            chat_template: None,
            batch_size: 512,
        }
    }
}

/// Detect available GPUs
pub fn detect_gpus() -> GpuConfig {
    // Try CUDA detection
    #[cfg(has_cuda)]
    {
        if let Ok(count) = detect_cuda_devices() {
            if count == 0 {
                return GpuConfig::CpuOnly;
            }
            if count == 1 {
                let info = get_cuda_device_info(0).unwrap_or_default();
                return GpuConfig::SingleGpu {
                    device_id: 0,
                    name: info.name,
                    vram_mb: info.vram_mb,
                };
            }
            // Multiple GPUs - split by VRAM
            let devices: Vec<GpuDevice> = (0..count)
                .filter_map(|i| {
                    let info = get_cuda_device_info(i).ok()?;
                    Some(GpuDevice {
                        device_id: i,
                        name: info.name,
                        vram_mb: info.vram_mb,
                        layer_fraction: 0.0, // Calculated below
                    })
                })
                .collect();

            // Distribute layers by VRAM proportion
            let total_vram: u64 = devices.iter().map(|d| d.vram_mb).sum();
            let devices: Vec<GpuDevice> = devices
                .into_iter()
                .map(|mut d| {
                    d.layer_fraction = d.vram_mb as f32 / total_vram as f32;
                    d
                })
                .collect();

            return GpuConfig::MultiGpu { devices };
        }
    }

    GpuConfig::CpuOnly
}

#[cfg(has_cuda)]
fn detect_cuda_devices() -> anyhow::Result<u32> {
    // This will be implemented by the backend
    // For now, return 0 (CPU only)
    Ok(0)
}

#[cfg(has_cuda)]
struct CudaDeviceInfo {
    name: String,
    vram_mb: u64,
}

#[cfg(has_cuda)]
impl Default for CudaDeviceInfo {
    fn default() -> Self {
        Self {
            name: "Unknown".into(),
            vram_mb: 0,
        }
    }
}

#[cfg(has_cuda)]
fn get_cuda_device_info(_device_id: u32) -> anyhow::Result<CudaDeviceInfo> {
    // This will be implemented by the backend
    Ok(CudaDeviceInfo::default())
}

/// Ollama model storage locations
pub fn ollama_model_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    // Windows default
    if let Ok(home) = std::env::var("USERPROFILE") {
        paths.push(PathBuf::from(home).join(".ollama").join("models"));
    }

    // Custom OLLAMA_MODELS env var
    if let Ok(custom) = std::env::var("OLLAMA_MODELS") {
        paths.push(PathBuf::from(custom));
    }

    paths
}

/// LM Studio model storage locations
pub fn lm_studio_model_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();

    // Windows default
    if let Ok(home) = std::env::var("USERPROFILE") {
        paths.push(PathBuf::from(home).join(".cache").join("lm-studio").join("models"));
    }

    // Custom path from LM Studio config
    if let Ok(appdata) = std::env::var("APPDATA") {
        let config_path = PathBuf::from(appdata).join("LM Studio").join("config.json");
        if config_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&config_path) {
                if let Ok(config) = serde_json::from_str::<serde_json::Value>(&content) {
                    if let Some(path) = config.get("modelsDirectory").and_then(|v| v.as_str()) {
                        paths.push(PathBuf::from(path));
                    }
                }
            }
        }
    }

    paths
}
```

**Step 3: Update lib.rs with module declarations**

Update `src/lib.rs`:

```rust
//! PCAI-Inference: Dual-backend LLM inference engine

pub mod backends;
pub mod config;

#[cfg(feature = "server")]
pub mod http;

#[cfg(feature = "ffi")]
pub mod ffi;

pub use backends::{
    Backend, BackendCapabilities, ChatMessage, ChatResponse,
    FinishReason, GenerateParams, InferenceBackend, ModelInfo,
    create_backend,
};
pub use config::{GpuConfig, GpuDevice, ModelConfig, detect_gpus};
```

**Step 4: Verify compilation**

```powershell
cargo check --no-default-features
```

Expected: Success (trait defined, no backends yet)

**Step 5: Commit trait definitions**

```powershell
git add Deploy/pcai-inference/src/
git commit -m "feat(pcai-inference): define InferenceBackend trait and config types"
```

---

## Task 3: HTTP Server (Reuse from rust-functiongemma-runtime)

**Files:**
- Create: `Deploy/pcai-inference/src/http/mod.rs`
- Create: `Deploy/pcai-inference/src/http/chat.rs`
- Create: `Deploy/pcai-inference/src/http/models.rs`
- Reference: `Deploy/rust-functiongemma-runtime/src/lib.rs` (copy OpenAI structs)

**Step 1: Create HTTP module**

Create `src/http/mod.rs`:

```rust
//! OpenAI-compatible HTTP server

mod chat;
mod models;

use axum::{routing::{get, post}, Router};
use std::{net::SocketAddr, sync::Arc};
use tokio::sync::RwLock;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

use crate::backends::InferenceBackend;

/// Shared server state
pub struct AppState {
    pub backend: Arc<RwLock<Box<dyn InferenceBackend>>>,
}

/// Create the Axum router
pub fn create_router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/v1/chat/completions", post(chat::chat_completions))
        .route("/v1/models", get(models::list_models))
        .route("/health", get(health_check))
        .layer(CorsLayer::permissive())
        .layer(TraceLayer::new_for_http())
        .with_state(state)
}

async fn health_check() -> &'static str {
    "OK"
}

/// Run the HTTP server
pub async fn run_server() -> anyhow::Result<()> {
    let backend = crate::create_backend(None)?;

    let state = Arc::new(AppState {
        backend: Arc::new(RwLock::new(backend)),
    });

    let app = create_router(state);

    let port: u16 = std::env::var("PCAI_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(8080);

    let addr = SocketAddr::from(([127, 0, 0, 1], port));
    tracing::info!("Listening on http://{}", addr);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;

    Ok(())
}
```

**Step 2: Create chat completions endpoint**

Create `src/http/chat.rs`:

```rust
//! /v1/chat/completions endpoint (OpenAI-compatible)

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{sync::Arc, time::{SystemTime, UNIX_EPOCH}};

use crate::backends::{ChatMessage, GenerateParams, FinishReason};
use super::AppState;

/// OpenAI-compatible chat completion request
#[derive(Debug, Deserialize)]
pub struct ChatCompletionRequest {
    pub model: Option<String>,
    pub messages: Vec<RequestMessage>,
    pub tools: Option<Value>,
    pub tool_choice: Option<Value>,
    #[serde(default = "default_temperature")]
    pub temperature: f32,
    #[serde(default = "default_max_tokens")]
    pub max_tokens: u32,
    pub top_p: Option<f32>,
    pub top_k: Option<u32>,
    pub stop: Option<Value>,
    pub seed: Option<u64>,
    pub stream: Option<bool>,
}

fn default_temperature() -> f32 { 0.7 }
fn default_max_tokens() -> u32 { 2048 }

#[derive(Debug, Deserialize)]
pub struct RequestMessage {
    pub role: String,
    pub content: Option<String>,
    pub tool_calls: Option<Value>,
}

/// OpenAI-compatible chat completion response
#[derive(Debug, Serialize)]
pub struct ChatCompletionResponse {
    pub id: String,
    pub object: String,
    pub created: u64,
    pub model: String,
    pub choices: Vec<Choice>,
    pub usage: Usage,
}

#[derive(Debug, Serialize)]
pub struct Choice {
    pub index: u32,
    pub message: ResponseMessage,
    pub finish_reason: String,
}

#[derive(Debug, Serialize)]
pub struct ResponseMessage {
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Value>,
}

#[derive(Debug, Serialize)]
pub struct Usage {
    pub prompt_tokens: u32,
    pub completion_tokens: u32,
    pub total_tokens: u32,
}

#[derive(Debug, Serialize)]
struct ApiError {
    message: String,
    #[serde(rename = "type")]
    error_type: String,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: ApiError,
}

impl IntoResponse for ErrorResponse {
    fn into_response(self) -> Response {
        (StatusCode::BAD_REQUEST, Json(self)).into_response()
    }
}

pub async fn chat_completions(
    State(state): State<Arc<AppState>>,
    Json(request): Json<ChatCompletionRequest>,
) -> Result<Json<ChatCompletionResponse>, ErrorResponse> {
    let backend = state.backend.read().await;

    if !backend.is_loaded() {
        return Err(ErrorResponse {
            error: ApiError {
                message: "No model loaded".into(),
                error_type: "invalid_request_error".into(),
            },
        });
    }

    // Convert request messages to backend format
    let messages: Vec<ChatMessage> = request.messages
        .into_iter()
        .map(|m| ChatMessage {
            role: m.role,
            content: m.content,
            tool_calls: m.tool_calls,
        })
        .collect();

    // Build generation params
    let params = GenerateParams {
        temperature: request.temperature,
        top_p: request.top_p.unwrap_or(0.9),
        top_k: request.top_k.unwrap_or(40),
        max_tokens: request.max_tokens,
        stop_sequences: parse_stop_sequences(request.stop),
        seed: request.seed,
    };

    // Generate response
    let response = backend.generate(messages, params).await.map_err(|e| {
        ErrorResponse {
            error: ApiError {
                message: e.to_string(),
                error_type: "internal_error".into(),
            },
        }
    })?;

    // Build OpenAI-compatible response
    let created = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs();

    let finish_reason = match response.finish_reason {
        FinishReason::Stop => "stop",
        FinishReason::Length => "length",
        FinishReason::ToolCalls => "tool_calls",
    };

    Ok(Json(ChatCompletionResponse {
        id: format!("pcai-{}", created),
        object: "chat.completion".into(),
        created,
        model: request.model.unwrap_or_else(|| "pcai-inference".into()),
        choices: vec![Choice {
            index: 0,
            message: ResponseMessage {
                role: "assistant".into(),
                content: response.content,
                tool_calls: response.tool_calls,
            },
            finish_reason: finish_reason.into(),
        }],
        usage: Usage {
            prompt_tokens: 0, // TODO: Implement token counting
            completion_tokens: response.tokens_generated,
            total_tokens: response.tokens_generated,
        },
    }))
}

fn parse_stop_sequences(stop: Option<Value>) -> Vec<String> {
    match stop {
        Some(Value::String(s)) => vec![s],
        Some(Value::Array(arr)) => arr
            .into_iter()
            .filter_map(|v| v.as_str().map(String::from))
            .collect(),
        _ => vec![],
    }
}
```

**Step 3: Create models endpoint**

Create `src/http/models.rs`:

```rust
//! /v1/models endpoint

use axum::{extract::State, Json};
use serde::Serialize;
use std::sync::Arc;

use super::AppState;

#[derive(Debug, Serialize)]
pub struct ModelsResponse {
    pub object: String,
    pub data: Vec<ModelObject>,
}

#[derive(Debug, Serialize)]
pub struct ModelObject {
    pub id: String,
    pub object: String,
    pub owned_by: String,
}

pub async fn list_models(
    State(state): State<Arc<AppState>>,
) -> Json<ModelsResponse> {
    let backend = state.backend.read().await;

    let data: Vec<ModelObject> = backend
        .list_models()
        .into_iter()
        .map(|m| ModelObject {
            id: m.id,
            object: "model".into(),
            owned_by: format!("{:?}", m.backend).to_lowercase(),
        })
        .collect();

    Json(ModelsResponse {
        object: "list".into(),
        data,
    })
}
```

**Step 4: Verify HTTP module compiles**

```powershell
cargo check --features server --no-default-features
```

Expected: Compilation errors about missing backend (expected, backends not implemented yet)

**Step 5: Commit HTTP server**

```powershell
git add Deploy/pcai-inference/src/http/
git commit -m "feat(pcai-inference): add OpenAI-compatible HTTP server"
```

---

## Task 4: llama_cpp-rs Backend Implementation (PARALLEL)

**Files:**
- Create: `Deploy/pcai-inference/src/backends/llamacpp.rs`

**Note:** This task can run in parallel with Task 5 (mistralrs backend).

**Step 1: Create llama_cpp backend stub**

Create `src/backends/llamacpp.rs`:

```rust
//! llama.cpp backend via llama-cpp-2 crate
//!
//! Provides broadest GGUF model compatibility for Ollama/LM Studio models.

use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

use super::{
    Backend, BackendCapabilities, ChatMessage, ChatResponse,
    FinishReason, GenerateParams, InferenceBackend, ModelInfo,
};
use crate::config::ModelConfig;

/// llama.cpp backend state
pub struct LlamaCppBackend {
    model: Option<Arc<Mutex<LlamaCppModel>>>,
    model_info: Option<ModelInfo>,
}

struct LlamaCppModel {
    // Will hold llama-cpp-2 model instance
    // model: llama_cpp_2::LlamaModel,
    // ctx: llama_cpp_2::LlamaContext,
    _placeholder: (),
}

impl LlamaCppBackend {
    pub fn new() -> anyhow::Result<Self> {
        tracing::info!("Initializing llama.cpp backend");
        Ok(Self {
            model: None,
            model_info: None,
        })
    }
}

#[async_trait]
impl InferenceBackend for LlamaCppBackend {
    async fn load_model(&mut self, model_path: &Path, config: &ModelConfig) -> anyhow::Result<()> {
        tracing::info!("Loading GGUF model from {:?}", model_path);

        // Verify file exists and is GGUF
        if !model_path.exists() {
            anyhow::bail!("Model file not found: {:?}", model_path);
        }

        let ext = model_path.extension().and_then(|e| e.to_str());
        if ext != Some("gguf") {
            anyhow::bail!("Expected .gguf file, got: {:?}", ext);
        }

        // TODO: Implement actual model loading with llama-cpp-2
        // let params = llama_cpp_2::LlamaModelParams::default()
        //     .with_n_gpu_layers(config.gpu_layers);
        // let model = llama_cpp_2::LlamaModel::load_from_file(model_path, params)?;

        self.model_info = Some(ModelInfo {
            id: model_path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("unknown")
                .to_string(),
            backend: Backend::LlamaCpp,
            architecture: "unknown".into(), // TODO: Read from GGUF metadata
            quantization: None, // TODO: Read from GGUF metadata
            context_length: config.context_length.unwrap_or(4096),
        });

        self.model = Some(Arc::new(Mutex::new(LlamaCppModel {
            _placeholder: (),
        })));

        tracing::info!("Model loaded successfully");
        Ok(())
    }

    async fn unload_model(&mut self) -> anyhow::Result<()> {
        self.model = None;
        self.model_info = None;
        tracing::info!("Model unloaded");
        Ok(())
    }

    fn is_loaded(&self) -> bool {
        self.model.is_some()
    }

    async fn generate(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
    ) -> anyhow::Result<ChatResponse> {
        let _model = self.model.as_ref()
            .ok_or_else(|| anyhow::anyhow!("No model loaded"))?;

        // TODO: Implement actual generation with llama-cpp-2
        // 1. Apply chat template to messages
        // 2. Tokenize prompt
        // 3. Run inference loop
        // 4. Decode tokens to text

        tracing::debug!("Generating response for {} messages", messages.len());
        tracing::debug!("Params: temp={}, max_tokens={}", params.temperature, params.max_tokens);

        // Placeholder response
        Ok(ChatResponse {
            content: Some("llama.cpp backend not yet implemented".into()),
            tool_calls: None,
            finish_reason: FinishReason::Stop,
            tokens_generated: 0,
        })
    }

    async fn generate_streaming(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
        mut on_token: Box<dyn FnMut(&str) + Send>,
    ) -> anyhow::Result<ChatResponse> {
        let _model = self.model.as_ref()
            .ok_or_else(|| anyhow::anyhow!("No model loaded"))?;

        // TODO: Implement streaming generation
        // Similar to generate() but call on_token for each decoded token

        on_token("llama.cpp ");
        on_token("streaming ");
        on_token("not yet implemented");

        Ok(ChatResponse {
            content: Some("llama.cpp streaming not yet implemented".into()),
            tool_calls: None,
            finish_reason: FinishReason::Stop,
            tokens_generated: 3,
        })
    }

    fn list_models(&self) -> Vec<ModelInfo> {
        self.model_info.clone().into_iter().collect()
    }

    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            supports_gpu: cfg!(has_cuda),
            supports_streaming: true,
            supports_tool_calls: true,
            supports_vision: false, // llama.cpp has limited vision support
            max_context_length: 128_000, // Depends on model
        }
    }

    fn backend_type(&self) -> Backend {
        Backend::LlamaCpp
    }
}
```

**Step 2: Add llama-cpp-2 dependency and implement**

Update `Cargo.toml` to use actual llama-cpp-2:

```toml
# Under [dependencies]
llama-cpp-2 = { version = "0.1", features = ["cuda"], optional = true }
```

**Step 3: Implement full llama-cpp-2 integration**

This requires updating `llamacpp.rs` with actual llama-cpp-2 API calls. Reference:
- https://docs.rs/llama-cpp-2/latest/llama_cpp_2/
- https://github.com/edgenai/llama_cpp-rs

Key implementation points:
1. `LlamaModel::load_from_file()` for model loading
2. `LlamaContext` for inference state
3. Token-by-token generation loop
4. Chat template application

**Step 4: Test model loading**

```powershell
# Create a simple test
cargo test --features llamacpp test_llamacpp_load
```

**Step 5: Commit llama_cpp backend**

```powershell
git add Deploy/pcai-inference/src/backends/llamacpp.rs
git commit -m "feat(pcai-inference): implement llama_cpp-rs backend"
```

---

## Task 5: mistralrs Backend Implementation (PARALLEL)

**Files:**
- Create: `Deploy/pcai-inference/src/backends/mistralrs.rs`

**Note:** This task can run in parallel with Task 4 (llama_cpp backend).

**Step 1: Create mistralrs backend wrapper**

Create `src/backends/mistralrs.rs`:

```rust
//! mistral.rs backend wrapper
//!
//! Provides multimodal support and advanced features when available.
//! Note: Windows CUDA builds may require WSL due to bindgen_cuda issues.

use async_trait::async_trait;
use std::path::Path;
use std::sync::Arc;
use tokio::sync::Mutex;

use super::{
    Backend, BackendCapabilities, ChatMessage, ChatResponse,
    FinishReason, GenerateParams, InferenceBackend, ModelInfo,
};
use crate::config::ModelConfig;

/// mistral.rs backend state
pub struct MistralRsBackend {
    // Will hold mistralrs pipeline
    // pipeline: Option<Arc<Mutex<mistralrs::Pipeline>>>,
    model_info: Option<ModelInfo>,
    is_loaded: bool,
}

impl MistralRsBackend {
    pub fn new() -> anyhow::Result<Self> {
        tracing::info!("Initializing mistral.rs backend");

        // Check if CUDA is available (may fail on Windows)
        #[cfg(has_cuda)]
        {
            tracing::warn!("mistral.rs CUDA on Windows may have build issues - see CUDA_BUILD_BLOCKING_ISSUE.md");
        }

        Ok(Self {
            model_info: None,
            is_loaded: false,
        })
    }
}

#[async_trait]
impl InferenceBackend for MistralRsBackend {
    async fn load_model(&mut self, model_path: &Path, config: &ModelConfig) -> anyhow::Result<()> {
        tracing::info!("Loading model via mistral.rs from {:?}", model_path);

        // Verify path exists
        if !model_path.exists() {
            anyhow::bail!("Model path not found: {:?}", model_path);
        }

        // TODO: Implement actual mistralrs model loading
        // Reference: https://github.com/EricLBuehler/mistral.rs
        //
        // For GGUF:
        // let loader = GGUFLoaderBuilder::new(
        //     GGUFSpecificConfig::default(),
        //     None, // chat_template
        //     None, // tokenizer
        //     Some(model_path.to_path_buf()),
        // ).build();
        //
        // let pipeline = loader.load_model(...)?;

        self.model_info = Some(ModelInfo {
            id: model_path.file_stem()
                .and_then(|s| s.to_str())
                .unwrap_or("unknown")
                .to_string(),
            backend: Backend::MistralRs,
            architecture: "auto-detected".into(),
            quantization: None,
            context_length: config.context_length.unwrap_or(4096),
        });

        self.is_loaded = true;
        tracing::info!("Model loaded via mistral.rs");
        Ok(())
    }

    async fn unload_model(&mut self) -> anyhow::Result<()> {
        self.model_info = None;
        self.is_loaded = false;
        tracing::info!("Model unloaded");
        Ok(())
    }

    fn is_loaded(&self) -> bool {
        self.is_loaded
    }

    async fn generate(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
    ) -> anyhow::Result<ChatResponse> {
        if !self.is_loaded {
            anyhow::bail!("No model loaded");
        }

        // TODO: Implement actual mistralrs generation
        // let request = Request {
        //     messages: convert_messages(messages),
        //     sampling_params: SamplingParams {
        //         temperature: Some(params.temperature as f64),
        //         top_p: Some(params.top_p as f64),
        //         max_len: Some(params.max_tokens as usize),
        //         ..Default::default()
        //     },
        //     ..Default::default()
        // };
        // let response = pipeline.run(request).await?;

        tracing::debug!("mistral.rs generate: {} messages", messages.len());

        Ok(ChatResponse {
            content: Some("mistral.rs backend not yet implemented".into()),
            tool_calls: None,
            finish_reason: FinishReason::Stop,
            tokens_generated: 0,
        })
    }

    async fn generate_streaming(
        &self,
        messages: Vec<ChatMessage>,
        params: GenerateParams,
        mut on_token: Box<dyn FnMut(&str) + Send>,
    ) -> anyhow::Result<ChatResponse> {
        if !self.is_loaded {
            anyhow::bail!("No model loaded");
        }

        // TODO: Implement streaming with mistralrs
        // mistralrs has built-in streaming support via channels

        on_token("mistral.rs ");
        on_token("streaming ");
        on_token("not yet implemented");

        Ok(ChatResponse {
            content: Some("mistral.rs streaming not yet implemented".into()),
            tool_calls: None,
            finish_reason: FinishReason::Stop,
            tokens_generated: 3,
        })
    }

    fn list_models(&self) -> Vec<ModelInfo> {
        self.model_info.clone().into_iter().collect()
    }

    fn capabilities(&self) -> BackendCapabilities {
        BackendCapabilities {
            supports_gpu: cfg!(has_cuda), // Windows CUDA may not work
            supports_streaming: true,
            supports_tool_calls: true,
            supports_vision: true, // mistral.rs excels at multimodal
            max_context_length: 128_000,
        }
    }

    fn backend_type(&self) -> Backend {
        Backend::MistralRs
    }
}
```

**Step 2: Add mistralrs dependency**

Update `Cargo.toml`:

```toml
# Under [dependencies]
mistralrs = { version = "0.3", optional = true, features = ["cuda"] }
```

**Step 3: Verify compilation**

```powershell
cargo check --features mistralrs-backend --no-default-features
```

**Step 4: Commit mistralrs backend**

```powershell
git add Deploy/pcai-inference/src/backends/mistralrs.rs
git commit -m "feat(pcai-inference): implement mistralrs backend wrapper"
```

---

## Task 6: FFI Exports for PowerShell

**Files:**
- Create: `Deploy/pcai-inference/src/ffi/mod.rs`
- Create: `Deploy/pcai-inference/src/ffi/types.rs`

**Step 1: Create FFI module**

Create `src/ffi/mod.rs`:

```rust
//! C FFI exports for PowerShell integration
//!
//! Provides low-latency direct calls from PowerShell via P/Invoke.

mod types;

use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::ptr;
use std::sync::OnceLock;
use tokio::runtime::Runtime;

use crate::backends::{create_backend, InferenceBackend, GenerateParams, ChatMessage};
use crate::config::ModelConfig;

pub use types::*;

// Global state for FFI
static RUNTIME: OnceLock<Runtime> = OnceLock::new();
static BACKEND: OnceLock<tokio::sync::Mutex<Box<dyn InferenceBackend>>> = OnceLock::new();

fn get_runtime() -> &'static Runtime {
    RUNTIME.get_or_init(|| {
        tokio::runtime::Builder::new_multi_thread()
            .enable_all()
            .build()
            .expect("Failed to create Tokio runtime")
    })
}

/// Initialize the inference backend
///
/// # Safety
/// backend_name must be a valid null-terminated C string or null
#[no_mangle]
pub unsafe extern "C" fn pcai_init(backend_name: *const c_char) -> FfiResult {
    let backend_type = if backend_name.is_null() {
        None
    } else {
        let name = CStr::from_ptr(backend_name).to_string_lossy();
        match name.as_ref() {
            "llamacpp" => Some(crate::backends::Backend::LlamaCpp),
            "mistralrs" => Some(crate::backends::Backend::MistralRs),
            _ => return FfiResult::error("Unknown backend"),
        }
    };

    match create_backend(backend_type) {
        Ok(backend) => {
            let _ = BACKEND.set(tokio::sync::Mutex::new(backend));
            FfiResult::ok()
        }
        Err(e) => FfiResult::error(&e.to_string()),
    }
}

/// Load a model from the given path
///
/// # Safety
/// model_path must be a valid null-terminated C string
#[no_mangle]
pub unsafe extern "C" fn pcai_load_model(
    model_path: *const c_char,
    gpu_layers: i32,
) -> FfiResult {
    if model_path.is_null() {
        return FfiResult::error("model_path is null");
    }

    let path = CStr::from_ptr(model_path).to_string_lossy();
    let config = ModelConfig {
        model_path: path.as_ref().into(),
        gpu_layers,
        ..Default::default()
    };

    let Some(backend) = BACKEND.get() else {
        return FfiResult::error("Backend not initialized - call pcai_init first");
    };

    let rt = get_runtime();
    let result = rt.block_on(async {
        let mut backend = backend.lock().await;
        backend.load_model(&config.model_path, &config).await
    });

    match result {
        Ok(()) => FfiResult::ok(),
        Err(e) => FfiResult::error(&e.to_string()),
    }
}

/// Generate a response (blocking, non-streaming)
///
/// # Safety
/// - prompt must be a valid null-terminated C string
/// - Returns a heap-allocated string that must be freed with pcai_free_string
#[no_mangle]
pub unsafe extern "C" fn pcai_generate(
    prompt: *const c_char,
    max_tokens: u32,
    temperature: f32,
) -> *mut c_char {
    if prompt.is_null() {
        return ptr::null_mut();
    }

    let prompt_str = CStr::from_ptr(prompt).to_string_lossy();

    let Some(backend) = BACKEND.get() else {
        return ptr::null_mut();
    };

    let messages = vec![ChatMessage {
        role: "user".into(),
        content: Some(prompt_str.into_owned()),
        tool_calls: None,
    }];

    let params = GenerateParams {
        temperature,
        max_tokens,
        ..Default::default()
    };

    let rt = get_runtime();
    let result = rt.block_on(async {
        let backend = backend.lock().await;
        backend.generate(messages, params).await
    });

    match result {
        Ok(response) => {
            let text = response.content.unwrap_or_default();
            CString::new(text).map(|s| s.into_raw()).unwrap_or(ptr::null_mut())
        }
        Err(_) => ptr::null_mut(),
    }
}

/// Generate with streaming callback
///
/// # Safety
/// - prompt must be a valid null-terminated C string
/// - callback will be called with each token (null-terminated)
/// - user_data is passed through to callback
#[no_mangle]
pub unsafe extern "C" fn pcai_generate_streaming(
    prompt: *const c_char,
    max_tokens: u32,
    temperature: f32,
    callback: Option<extern "C" fn(*const c_char, *mut std::ffi::c_void)>,
    user_data: *mut std::ffi::c_void,
) -> FfiResult {
    if prompt.is_null() {
        return FfiResult::error("prompt is null");
    }

    let Some(callback) = callback else {
        return FfiResult::error("callback is null");
    };

    let prompt_str = CStr::from_ptr(prompt).to_string_lossy().into_owned();

    let Some(backend) = BACKEND.get() else {
        return FfiResult::error("Backend not initialized");
    };

    let messages = vec![ChatMessage {
        role: "user".into(),
        content: Some(prompt_str),
        tool_calls: None,
    }];

    let params = GenerateParams {
        temperature,
        max_tokens,
        ..Default::default()
    };

    // Wrap callback for Rust
    let user_data_ptr = user_data as usize; // Make it Send
    let on_token: Box<dyn FnMut(&str) + Send> = Box::new(move |token: &str| {
        if let Ok(c_str) = CString::new(token) {
            callback(c_str.as_ptr(), user_data_ptr as *mut std::ffi::c_void);
        }
    });

    let rt = get_runtime();
    let result = rt.block_on(async {
        let backend = backend.lock().await;
        backend.generate_streaming(messages, params, on_token).await
    });

    match result {
        Ok(_) => FfiResult::ok(),
        Err(e) => FfiResult::error(&e.to_string()),
    }
}

/// Free a string allocated by pcai_generate
///
/// # Safety
/// ptr must be a string returned by pcai_generate, or null
#[no_mangle]
pub unsafe extern "C" fn pcai_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        drop(CString::from_raw(ptr));
    }
}

/// Cleanup and shutdown
#[no_mangle]
pub extern "C" fn pcai_shutdown() {
    // Backend will be dropped when the process exits
    // This is mainly for explicit cleanup if needed
}
```

**Step 2: Create FFI types**

Create `src/ffi/types.rs`:

```rust
//! FFI type definitions

use std::ffi::CString;
use std::os::raw::c_char;

/// Result type for FFI calls
#[repr(C)]
pub struct FfiResult {
    pub success: bool,
    pub error_message: *mut c_char,
}

impl FfiResult {
    pub fn ok() -> Self {
        Self {
            success: true,
            error_message: std::ptr::null_mut(),
        }
    }

    pub fn error(msg: &str) -> Self {
        let error_message = CString::new(msg)
            .map(|s| s.into_raw())
            .unwrap_or(std::ptr::null_mut());

        Self {
            success: false,
            error_message,
        }
    }
}

/// Free an FfiResult's error message
///
/// # Safety
/// result must be a valid FfiResult
#[no_mangle]
pub unsafe extern "C" fn pcai_free_result(result: *mut FfiResult) {
    if !result.is_null() {
        let result = &mut *result;
        if !result.error_message.is_null() {
            drop(CString::from_raw(result.error_message));
            result.error_message = std::ptr::null_mut();
        }
    }
}
```

**Step 3: Update lib.rs**

Add FFI module export:

```rust
#[cfg(feature = "ffi")]
pub mod ffi;
```

**Step 4: Verify FFI compilation**

```powershell
cargo build --features ffi --release
```

**Step 5: Commit FFI exports**

```powershell
git add Deploy/pcai-inference/src/ffi/
git commit -m "feat(pcai-inference): add C FFI exports for PowerShell"
```

---

## Task 7: Integration Tests

**Files:**
- Create: `Deploy/pcai-inference/tests/integration.rs`
- Create: `Deploy/pcai-inference/tests/common/mod.rs`

**Step 1: Create test utilities**

Create `tests/common/mod.rs`:

```rust
//! Common test utilities

use std::path::PathBuf;

/// Get path to test GGUF model (if available)
pub fn test_model_path() -> Option<PathBuf> {
    // Check for test model in various locations
    let candidates = [
        // CI/CD test model
        PathBuf::from("tests/fixtures/tiny-model.gguf"),
        // Local Ollama models
        dirs::home_dir()?.join(".ollama/models/library/tinyllama"),
    ];

    candidates.into_iter().find(|p| p.exists())
}

/// Skip test if no model available
#[macro_export]
macro_rules! require_model {
    () => {
        let Some(model_path) = common::test_model_path() else {
            eprintln!("Skipping test: no test model available");
            return;
        };
        model_path
    };
}
```

**Step 2: Create integration tests**

Create `tests/integration.rs`:

```rust
//! Integration tests for pcai-inference

mod common;

use pcai_inference::{create_backend, Backend, ModelConfig, GenerateParams, ChatMessage};

#[tokio::test]
async fn test_backend_creation_llamacpp() {
    #[cfg(feature = "llamacpp")]
    {
        let backend = create_backend(Some(Backend::LlamaCpp));
        assert!(backend.is_ok(), "Failed to create llama.cpp backend");

        let backend = backend.unwrap();
        assert_eq!(backend.backend_type(), Backend::LlamaCpp);
        assert!(!backend.is_loaded());
    }
}

#[tokio::test]
async fn test_backend_creation_mistralrs() {
    #[cfg(feature = "mistralrs-backend")]
    {
        let backend = create_backend(Some(Backend::MistralRs));
        assert!(backend.is_ok(), "Failed to create mistral.rs backend");

        let backend = backend.unwrap();
        assert_eq!(backend.backend_type(), Backend::MistralRs);
    }
}

#[tokio::test]
async fn test_model_loading() {
    let model_path = require_model!();

    let mut backend = create_backend(None).expect("Backend creation failed");

    let config = ModelConfig {
        model_path: model_path.clone(),
        gpu_layers: 0, // CPU only for tests
        ..Default::default()
    };

    let result = backend.load_model(&model_path, &config).await;
    assert!(result.is_ok(), "Model loading failed: {:?}", result.err());
    assert!(backend.is_loaded());
}

#[tokio::test]
async fn test_generation() {
    let model_path = require_model!();

    let mut backend = create_backend(None).expect("Backend creation failed");

    let config = ModelConfig {
        model_path: model_path.clone(),
        gpu_layers: 0,
        ..Default::default()
    };

    backend.load_model(&model_path, &config).await.unwrap();

    let messages = vec![ChatMessage {
        role: "user".into(),
        content: Some("Hello".into()),
        tool_calls: None,
    }];

    let params = GenerateParams {
        temperature: 0.7,
        max_tokens: 10,
        ..Default::default()
    };

    let response = backend.generate(messages, params).await;
    assert!(response.is_ok(), "Generation failed: {:?}", response.err());

    let response = response.unwrap();
    assert!(response.content.is_some() || response.tool_calls.is_some());
}
```

**Step 3: Run tests**

```powershell
cargo test --all-features
```

**Step 4: Commit tests**

```powershell
git add Deploy/pcai-inference/tests/
git commit -m "test(pcai-inference): add integration tests"
```

---

## Task 8: PC-AI.ps1 Integration

**Files:**
- Modify: `PC-AI.ps1` (add InferenceBackend parameter)
- Create: `Modules/PcaiInference.psm1` (FFI wrapper module)

**Step 1: Create PowerShell FFI module**

Create `Modules/PcaiInference.psm1`:

```powershell
# PcaiInference.psm1 - FFI wrapper for pcai-inference

$script:DllPath = Join-Path $PSScriptRoot "..\Deploy\pcai-inference\target\release\pcai_inference.dll"
$script:Initialized = $false

# Define P/Invoke signatures
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public struct FfiResult {
    [MarshalAs(UnmanagedType.I1)]
    public bool Success;
    public IntPtr ErrorMessage;
}

public static class PcaiInference {
    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern FfiResult pcai_init(string backendName);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern FfiResult pcai_load_model(string modelPath, int gpuLayers);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr pcai_generate(string prompt, uint maxTokens, float temperature);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_free_string(IntPtr ptr);

    [DllImport("pcai_inference.dll", CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_shutdown();
}
"@ -PassThru | Out-Null

function Initialize-PcaiInference {
    [CmdletBinding()]
    param(
        [ValidateSet('auto', 'llamacpp', 'mistralrs')]
        [string]$Backend = 'auto'
    )

    if ($script:Initialized) {
        Write-Verbose "Already initialized"
        return
    }

    $backendName = if ($Backend -eq 'auto') { $null } else { $Backend }
    $result = [PcaiInference]::pcai_init($backendName)

    if (-not $result.Success) {
        $error = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($result.ErrorMessage)
        throw "Failed to initialize: $error"
    }

    $script:Initialized = $true
    Write-Verbose "Initialized with backend: $Backend"
}

function Import-PcaiModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelPath,

        [int]$GpuLayers = -1
    )

    if (-not $script:Initialized) {
        Initialize-PcaiInference
    }

    $result = [PcaiInference]::pcai_load_model($ModelPath, $GpuLayers)

    if (-not $result.Success) {
        $error = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($result.ErrorMessage)
        throw "Failed to load model: $error"
    }

    Write-Verbose "Loaded model: $ModelPath"
}

function Invoke-PcaiGenerate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [uint32]$MaxTokens = 2048,

        [float]$Temperature = 0.7
    )

    if (-not $script:Initialized) {
        throw "Not initialized - call Initialize-PcaiInference first"
    }

    $ptr = [PcaiInference]::pcai_generate($Prompt, $MaxTokens, $Temperature)

    if ($ptr -eq [IntPtr]::Zero) {
        throw "Generation failed"
    }

    try {
        $response = [System.Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr)
        return $response
    }
    finally {
        [PcaiInference]::pcai_free_string($ptr)
    }
}

function Close-PcaiInference {
    [CmdletBinding()]
    param()

    if ($script:Initialized) {
        [PcaiInference]::pcai_shutdown()
        $script:Initialized = $false
    }
}

Export-ModuleMember -Function @(
    'Initialize-PcaiInference',
    'Import-PcaiModel',
    'Invoke-PcaiGenerate',
    'Close-PcaiInference'
)
```

**Step 2: Update PC-AI.ps1 with backend routing**

Add to `PC-AI.ps1`:

```powershell
param(
    # ... existing params ...

    [ValidateSet('auto', 'llamacpp', 'mistralrs', 'http')]
    [string]$InferenceBackend = 'auto',

    [string]$ModelPath,

    [switch]$UseNativeInference
)

# Load native inference module if requested
if ($UseNativeInference) {
    Import-Module "$PSScriptRoot\Modules\PcaiInference.psm1" -Force
    Initialize-PcaiInference -Backend $InferenceBackend

    if ($ModelPath) {
        Import-PcaiModel -ModelPath $ModelPath
    }
}
```

**Step 3: Test PowerShell integration**

```powershell
# Build the DLL first
cd C:\Users\david\PC_AI\Deploy\pcai-inference
cargo build --features ffi --release

# Test from PowerShell
Import-Module .\Modules\PcaiInference.psm1
Initialize-PcaiInference -Backend llamacpp -Verbose
```

**Step 4: Commit integration**

```powershell
git add Modules/PcaiInference.psm1 PC-AI.ps1
git commit -m "feat(pc-ai): integrate native Rust inference via FFI"
```

---

## Summary

| Task | Description | Parallel? | Dependencies |
|------|-------------|-----------|--------------|
| 1 | Project scaffolding | No | - |
| 2 | Backend trait & config | No | Task 1 |
| 3 | HTTP server | No | Task 2 |
| 4 | llama_cpp-rs backend | **Yes** | Task 2 |
| 5 | mistralrs backend | **Yes** | Task 2 |
| 6 | FFI exports | No | Task 4 or 5 |
| 7 | Integration tests | No | Task 4, 5, 6 |
| 8 | PC-AI.ps1 integration | No | Task 6 |

**Estimated effort:**
- Tasks 1-3: ~2 hours (scaffolding, sequential)
- Tasks 4-5: ~4 hours each (parallel = 4 hours total)
- Tasks 6-8: ~3 hours (integration, sequential)
- **Total: ~9 hours**

---

Plan complete and saved to `docs/plans/2026-01-30-pcai-inference-dual-backend.md`.

**Two execution options:**

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
