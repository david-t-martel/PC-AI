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
use uuid::Uuid;

use crate::{
    backends::{FinishReason, GenerateRequest, InferenceBackend},
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
) -> std::result::Result<Response, AppError> {
    let backend = state.backend.read().await;

    if !backend.is_loaded() {
        return Err(AppError::ModelNotLoaded);
    }

    let prompt_tokens = estimate_tokens(&req.prompt);
    let stop = req.stop.clone();
    let generate_req = GenerateRequest {
        prompt: req.prompt,
        max_tokens: req.max_tokens,
        temperature: req.temperature,
        top_p: req.top_p,
        stop: stop.clone().unwrap_or_default(),
    };

    let response = backend.generate(generate_req).await?;

    let (text, finish_reason) =
        apply_stop_sequences(&response.text, &stop, response.finish_reason);

    let completion_response = CompletionResponse {
        id: format!("cmpl-{}", Uuid::new_v4()),
        object: "text_completion".to_string(),
        created: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        model: "pcai-inference".to_string(),
        choices: vec![Choice {
            text,
            index: 0,
            finish_reason: Some(finish_reason_to_string(finish_reason)),
        }],
        usage: Usage {
            prompt_tokens,
            completion_tokens: response.tokens_generated,
            total_tokens: prompt_tokens + response.tokens_generated,
        },
    };

    Ok(Json(completion_response).into_response())
}

/// Chat completions endpoint
async fn chat_completions(
    State(state): State<Arc<AppState>>,
    Json(req): Json<ChatCompletionRequest>,
) -> std::result::Result<Response, AppError> {
    if req.stream.unwrap_or(false) {
        return Err(AppError(Error::InvalidInput(
            "Streaming is not supported".to_string(),
        )));
    }

    let backend = state.backend.read().await;

    if !backend.is_loaded() {
        return Err(AppError::ModelNotLoaded);
    }

    let prompt = build_chat_prompt(&req.messages)?;
    let prompt_tokens = estimate_tokens(&prompt);

    let stop = req.stop.clone();
    let generate_req = GenerateRequest {
        prompt,
        max_tokens: req.max_tokens,
        temperature: req.temperature,
        top_p: req.top_p,
        stop: stop.clone().unwrap_or_default(),
    };

    let response = backend.generate(generate_req).await?;
    let (content, finish_reason) =
        apply_stop_sequences(&response.text, &stop, response.finish_reason);

    let completion_response = ChatCompletionResponse {
        id: format!("chatcmpl-{}", Uuid::new_v4()),
        object: "chat.completion".to_string(),
        created: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_secs(),
        model: req.model.unwrap_or_else(|| "pcai-inference".to_string()),
        choices: vec![ChatChoice {
            index: 0,
            message: ChatMessageResponse {
                role: "assistant".to_string(),
                content,
            },
            finish_reason: Some(finish_reason_to_string(finish_reason)),
        }],
        usage: Usage {
            prompt_tokens,
            completion_tokens: response.tokens_generated,
            total_tokens: prompt_tokens + response.tokens_generated,
        },
    };

    Ok(Json(completion_response).into_response())
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

#[derive(Debug, Deserialize)]
struct ChatCompletionRequest {
    model: Option<String>,
    messages: Vec<ChatMessage>,
    #[serde(default)]
    max_tokens: Option<usize>,
    #[serde(default)]
    temperature: Option<f32>,
    #[serde(default)]
    top_p: Option<f32>,
    #[serde(default)]
    stop: Option<Vec<String>>,
    #[serde(default)]
    stream: Option<bool>,
}

#[derive(Debug, Deserialize)]
struct ChatMessage {
    role: String,
    content: String,
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

#[derive(Debug, Serialize)]
struct ChatCompletionResponse {
    id: String,
    object: String,
    created: u64,
    model: String,
    choices: Vec<ChatChoice>,
    usage: Usage,
}

#[derive(Debug, Serialize)]
struct ChatChoice {
    index: usize,
    message: ChatMessageResponse,
    finish_reason: Option<String>,
}

#[derive(Debug, Serialize)]
struct ChatMessageResponse {
    role: String,
    content: String,
}

// Error handling
#[derive(Debug)]
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

fn build_chat_prompt(messages: &[ChatMessage]) -> std::result::Result<String, AppError> {
    if messages.is_empty() {
        return Err(AppError(Error::InvalidInput(
            "messages must not be empty".to_string(),
        )));
    }

    let mut prompt = String::new();
    for message in messages {
        let role = message.role.to_lowercase();
        let role_label = match role.as_str() {
            "system" => "System",
            "user" => "User",
            "assistant" => "Assistant",
            "tool" => "Tool",
            _ => "User",
        };

        if !prompt.is_empty() {
            prompt.push('\n');
        }

        prompt.push_str(role_label);
        prompt.push_str(": ");
        prompt.push_str(message.content.trim());
    }

    prompt.push_str("\nAssistant: ");
    Ok(prompt)
}

fn estimate_tokens(text: &str) -> usize {
    if text.is_empty() {
        return 0;
    }

    let char_count = text.chars().count();
    let char_tokens = (char_count + 3) / 4;
    let word_tokens = text.split_whitespace().count();
    char_tokens.max(word_tokens).max(1)
}

fn apply_stop_sequences(
    text: &str,
    stop: &Option<Vec<String>>,
    finish_reason: FinishReason,
) -> (String, FinishReason) {
    let Some(stops) = stop else {
        return (text.to_string(), finish_reason);
    };

    let mut earliest: Option<usize> = None;
    for stop_seq in stops {
        if stop_seq.is_empty() {
            continue;
        }
        if let Some(idx) = text.find(stop_seq) {
            earliest = Some(match earliest {
                Some(prev) => prev.min(idx),
                None => idx,
            });
        }
    }

    match earliest {
        Some(idx) => (text[..idx].to_string(), FinishReason::Stop),
        None => (text.to_string(), finish_reason),
    }
}

fn finish_reason_to_string(reason: FinishReason) -> String {
    match reason {
        FinishReason::Stop => "stop".to_string(),
        FinishReason::Length => "length".to_string(),
        FinishReason::Error => "error".to_string(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_build_chat_prompt() {
        let messages = vec![
            ChatMessage {
                role: "system".to_string(),
                content: "You are helpful.".to_string(),
            },
            ChatMessage {
                role: "user".to_string(),
                content: "Hello".to_string(),
            },
        ];

        let prompt = build_chat_prompt(&messages).unwrap();
        assert!(prompt.contains("System: You are helpful."));
        assert!(prompt.contains("User: Hello"));
        assert!(prompt.ends_with("Assistant: "));
    }

    #[test]
    fn test_estimate_tokens() {
        assert_eq!(estimate_tokens(""), 0);
        assert!(estimate_tokens("hello") >= 1);
        assert!(estimate_tokens("hello world") >= 2);
    }

    #[test]
    fn test_apply_stop_sequences() {
        let input = "Hello world STOP and more";
        let stops = Some(vec!["STOP".to_string()]);
        let (text, reason) = apply_stop_sequences(input, &stops, FinishReason::Length);
        assert_eq!(text.trim_end(), "Hello world");
        assert!(matches!(reason, FinishReason::Stop));
    }
}
