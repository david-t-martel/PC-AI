//! HTTP server with OpenAI-compatible API

use axum::{
    extract::State,
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use std::sync::Arc;
use tokio::sync::RwLock;
use tower_http::cors::CorsLayer;
use tower_http::trace::TraceLayer;

use crate::{
    backends::{GenerateRequest, InferenceBackend},
    config::ServerConfig,
    Error, Result,
};

/// Shared application state
pub struct AppState {
    backend: Arc<RwLock<Box<dyn InferenceBackend>>>,
}

/// Run the HTTP server
pub async fn run_server(
    config: ServerConfig,
    backend: Box<dyn InferenceBackend>,
) -> Result<()> {
    tracing::info!("Starting HTTP server on {}:{}", config.host, config.port);

    let state = AppState {
        backend: Arc::new(RwLock::new(backend)),
    };

    let mut app = Router::new()
        .route("/health", get(health_check))
        .route("/v1/completions", post(completions))
        .route("/v1/chat/completions", post(chat_completions))
        .with_state(Arc::new(state))
        .layer(TraceLayer::new_for_http());

    if config.cors {
        app = app.layer(CorsLayer::permissive());
    }

    let addr = format!("{}:{}", config.host, config.port);
    let listener = tokio::net::TcpListener::bind(&addr).await?;

    tracing::info!("Server listening on {}", addr);

    axum::serve(listener, app)
        .await
        .map_err(|e| Error::Other(e.into()))?;

    Ok(())
}

/// Health check endpoint
async fn health_check(State(state): State<Arc<AppState>>) -> impl IntoResponse {
    let backend = state.backend.read().await;
    let status = if backend.is_loaded() {
        "ready"
    } else {
        "not_ready"
    };

    Json(serde_json::json!({
        "status": status,
        "backend": backend.backend_name(),
    }))
}

/// OpenAI-compatible completions endpoint
async fn completions(
    State(state): State<Arc<AppState>>,
    Json(req): Json<CompletionRequest>,
) -> Result<Response, AppError> {
    let backend = state.backend.read().await;

    if !backend.is_loaded() {
        return Err(AppError::ModelNotLoaded);
    }

    let generate_req = GenerateRequest {
        prompt: req.prompt,
        max_tokens: req.max_tokens,
        temperature: req.temperature,
        top_p: req.top_p,
        stop: req.stop.unwrap_or_default(),
    };

    let response = backend.generate(generate_req).await?;

    let completion_response = CompletionResponse {
        id: format!("cmpl-{}", uuid::Uuid::new_v4()),
        object: "text_completion".to_string(),
        created: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        model: "pcai-inference".to_string(),
        choices: vec![Choice {
            text: response.text,
            index: 0,
            finish_reason: Some(format!("{:?}", response.finish_reason).to_lowercase()),
        }],
        usage: Usage {
            prompt_tokens: 0, // TODO: Implement token counting
            completion_tokens: response.tokens_generated,
            total_tokens: response.tokens_generated,
        },
    };

    Ok(Json(completion_response).into_response())
}

/// Chat completions endpoint (stub)
async fn chat_completions(
    State(_state): State<Arc<AppState>>,
    Json(_req): Json<serde_json::Value>,
) -> Result<Response, AppError> {
    // TODO: Implement chat completions
    Err(AppError::NotImplemented)
}

// Request/Response types
#[derive(Debug, Deserialize)]
struct CompletionRequest {
    prompt: String,
    #[serde(default)]
    max_tokens: Option<usize>,
    #[serde(default)]
    temperature: Option<f32>,
    #[serde(default)]
    top_p: Option<f32>,
    #[serde(default)]
    stop: Option<Vec<String>>,
}

#[derive(Debug, Serialize)]
struct CompletionResponse {
    id: String,
    object: String,
    created: u64,
    model: String,
    choices: Vec<Choice>,
    usage: Usage,
}

#[derive(Debug, Serialize)]
struct Choice {
    text: String,
    index: usize,
    finish_reason: Option<String>,
}

#[derive(Debug, Serialize)]
struct Usage {
    prompt_tokens: usize,
    completion_tokens: usize,
    total_tokens: usize,
}

// Error handling
struct AppError(Error);

impl From<Error> for AppError {
    fn from(err: Error) -> Self {
        AppError(err)
    }
}

impl AppError {
    fn model_not_loaded() -> Self {
        AppError(Error::ModelNotLoaded)
    }

    const ModelNotLoaded: Self = AppError(Error::ModelNotLoaded);
    const NotImplemented: Self = AppError(Error::Backend("Not implemented".to_string()));
}

impl IntoResponse for AppError {
    fn into_response(self) -> Response {
        let (status, message) = match &self.0 {
            Error::ModelNotLoaded => (StatusCode::SERVICE_UNAVAILABLE, "Model not loaded"),
            Error::Backend(msg) => (StatusCode::INTERNAL_SERVER_ERROR, msg.as_str()),
            Error::InvalidInput(msg) => (StatusCode::BAD_REQUEST, msg.as_str()),
            _ => (StatusCode::INTERNAL_SERVER_ERROR, "Internal server error"),
        };

        let body = Json(serde_json::json!({
            "error": {
                "message": message,
                "type": "server_error",
            }
        }));

        (status, body).into_response()
    }
}

// Add uuid dependency for request IDs
use uuid::Uuid;
