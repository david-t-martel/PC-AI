use axum::{
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{env, net::SocketAddr, time::{SystemTime, UNIX_EPOCH}};
use std::fs;
#[cfg(feature = "model")]
use std::path::{Path, PathBuf};
use tracing_subscriber::EnvFilter;

#[cfg(feature = "model")]
use candle_core::{DType, Device, Tensor};
#[cfg(feature = "model")]
use candle_nn::{VarBuilder, VarMap};
#[cfg(feature = "model")]
use rust_functiongemma_train::{Config, Model};
#[cfg(feature = "model")]
use tokenizers::Tokenizer;

#[cfg(feature = "model")]
mod model_support;

#[derive(Debug, Deserialize)]
pub struct ChatCompletionRequest {
    pub model: Option<String>,
    pub messages: Vec<Message>,
    pub tools: Option<Value>,
    pub tool_choice: Option<Value>,
    pub temperature: Option<f64>,
    pub max_tokens: Option<u32>,
    // Additional OpenAI-compatible parameters
    pub top_p: Option<f64>,
    pub top_k: Option<u32>,
    pub frequency_penalty: Option<f64>,
    pub presence_penalty: Option<f64>,
    pub stop: Option<Value>,  // Can be string or array of strings
    pub seed: Option<i64>,
    pub user: Option<String>,
    pub n: Option<u32>,  // Number of completions (only 1 supported currently)
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Message {
    pub role: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Value>,
}

#[derive(Debug, Serialize)]
struct Choice {
    index: u32,
    message: Message,
    finish_reason: String,
}

#[derive(Debug, Serialize)]
struct Usage {
    prompt_tokens: u32,
    completion_tokens: u32,
    total_tokens: u32,
}

#[derive(Debug, Serialize)]
struct ChatCompletionResponse {
    id: String,
    object: String,
    created: u64,
    model: String,
    choices: Vec<Choice>,
    #[serde(skip_serializing_if = "Option::is_none")]
    usage: Option<Usage>,
}

#[derive(Debug, Serialize)]
struct ApiError {
    message: String,
    #[serde(rename = "type")]
    error_type: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    param: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    code: Option<String>,
}

#[derive(Debug, Serialize)]
struct ErrorResponse {
    error: ApiError,
}

#[derive(Debug, Serialize)]
struct ModelInfo {
    id: String,
    object: String,
    owned_by: String,
    metadata: RouterMetadata,
}

#[derive(Debug, Serialize)]
struct ModelList {
    object: String,
    data: Vec<ModelInfo>,
}

#[derive(Debug, Serialize)]
struct ToolsMetadata {
    path: String,
    count: usize,
    loaded: bool,
}

#[derive(Debug, Serialize)]
struct LoraMetadata {
    path: String,
    r: usize,
}

#[derive(Debug, Serialize)]
struct RouterMetadata {
    version: String,
    model: String,
    tools: ToolsMetadata,
    engine: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    device: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    lora: Option<LoraMetadata>,
}

#[derive(Debug, Serialize)]
struct HealthResponse {
    status: String,
    metadata: RouterMetadata,
}

#[derive(Debug, Default)]
struct RouterPrompt {
    mode: Option<String>,
    system_prompt: Option<String>,
    user_request: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum RouterEngine {
    Heuristic,
    Model,
}

#[derive(Debug)]
struct InferenceResult {
    content: Option<String>,
    tool_calls: Option<Value>,
}

fn default_model() -> String {
    env::var("PCAI_ROUTER_MODEL").unwrap_or_else(|_| "functiongemma-270m-it".to_string())
}

fn tools_metadata() -> ToolsMetadata {
    let path = env::var("PCAI_TOOLS_PATH").unwrap_or_else(|_| "Config/pcai-tools.json".to_string());
    let mut count = 0usize;
    let mut loaded = false;
    if let Ok(contents) = fs::read_to_string(&path) {
        if let Ok(doc) = serde_json::from_str::<Value>(&contents) {
            if let Some(arr) = doc.get("tools").and_then(|v| v.as_array()) {
                count = arr.len();
                loaded = true;
            }
        }
    }

    ToolsMetadata { path, count, loaded }
}

fn router_metadata() -> RouterMetadata {
    let model = default_model();
    let engine = match router_engine() {
        RouterEngine::Heuristic => "heuristic",
        RouterEngine::Model => "model",
    };

    #[cfg(feature = "model")]
    let device = Some(device_label());
    #[cfg(not(feature = "model"))]
    let device = None;

    #[cfg(feature = "model")]
    let lora = lora_metadata();
    #[cfg(not(feature = "model"))]
    let lora = None;

    RouterMetadata {
        version: env!("CARGO_PKG_VERSION").to_string(),
        model,
        tools: tools_metadata(),
        engine: engine.to_string(),
        device,
        lora,
    }
}

impl ErrorResponse {
    fn bad_request(message: impl Into<String>, param: Option<String>) -> Self {
        Self {
            error: ApiError {
                message: message.into(),
                error_type: "invalid_request_error".to_string(),
                param,
                code: None,
            },
        }
    }

    fn internal_error(message: impl Into<String>) -> Self {
        Self {
            error: ApiError {
                message: message.into(),
                error_type: "server_error".to_string(),
                param: None,
                code: Some("internal_error".to_string()),
            },
        }
    }
}

impl IntoResponse for ErrorResponse {
    fn into_response(self) -> Response {
        let status = match self.error.error_type.as_str() {
            "invalid_request_error" => StatusCode::BAD_REQUEST,
            _ => StatusCode::INTERNAL_SERVER_ERROR,
        };
        (status, Json(self)).into_response()
    }
}

#[cfg(feature = "model")]
fn use_kv_cache() -> bool {
    env::var("PCAI_ROUTER_KV_CACHE")
        .unwrap_or_else(|_| "1".to_string())
        .to_lowercase()
        .as_str() != "0"
}

fn router_engine() -> RouterEngine {
    match env::var("PCAI_ROUTER_ENGINE").unwrap_or_else(|_| "heuristic".to_string()).to_lowercase().as_str() {
        "model" => RouterEngine::Model,
        _ => RouterEngine::Heuristic,
    }
}

async fn health() -> Json<Value> {
    let metadata = router_metadata();
    Json(json!(HealthResponse { status: "ok".to_string(), metadata }))
}

async fn list_models() -> Json<ModelList> {
    let model = default_model();
    let metadata = router_metadata();
    Json(ModelList {
        object: "list".to_string(),
        data: vec![ModelInfo {
            id: model,
            object: "model".to_string(),
            owned_by: "pcai".to_string(),
            metadata,
        }],
    })
}

fn last_user_message(messages: &[Message]) -> Option<&str> {
    messages.iter().rev().find(|m| m.role == "user").and_then(|m| m.content.as_deref())
}

fn parse_router_prompt(text: &str) -> RouterPrompt {
    let mut prompt = RouterPrompt::default();
    if let Some(idx) = text.find("[MODE]") {
        let rest = &text[idx + 6..];
        if let Some(end) = rest.find('\n') {
            prompt.mode = Some(rest[..end].trim().to_string());
        }
    }
    if let Some(idx) = text.find("[SYSTEM_PROMPT]") {
        let rest = &text[idx + 15..];
        if let Some(end) = rest.find("[USER_REQUEST]") {
            prompt.system_prompt = Some(rest[..end].trim().to_string());
        }
    }
    if let Some(idx) = text.find("[USER_REQUEST]") {
        prompt.user_request = text[idx + 14..].trim().to_string();
    } else {
        prompt.user_request = text.trim().to_string();
    }
    prompt
}

fn extract_args_from_text(text: &str) -> Option<Value> {
    if let Some(idx) = text.find("Arguments:") {
        let tail = text[idx + "Arguments:".len()..].trim();
        if let Ok(val) = serde_json::from_str::<Value>(tail) {
            return Some(val);
        }
    }
    let start = text.find('{')?;
    let end = text.rfind('}')?;
    if end > start {
        serde_json::from_str::<Value>(&text[start..=end]).ok()
    } else {
        None
    }
}

fn select_tool_by_name(text: &str, tools: &Value) -> Option<String> {
    let tools_arr = tools.as_array()?;
    let text_lower = text.to_lowercase();
    for tool in tools_arr {
        let name = tool.get("function")
            .and_then(|f| f.get("name"))
            .and_then(|n| n.as_str())?;
        if text_lower.contains(&name.to_lowercase()) {
            return Some(name.to_string());
        }
    }
    None
}

fn resolve_tool_choice(tool_choice: &Value) -> Option<String> {
    match tool_choice {
        Value::String(s) => {
            if s == "none" || s == "auto" { None } else { Some(s.to_string()) }
        }
        Value::Object(map) => map.get("function")
            .and_then(|f| f.get("name"))
            .and_then(|n| n.as_str())
            .map(|s| s.to_string()),
        _ => None,
    }
}

fn tool_choice_requires_tool(tool_choice: &Value) -> bool {
    match tool_choice {
        Value::String(s) => s.eq_ignore_ascii_case("required"),
        Value::Object(map) => {
            let is_function = map.get("type")
                .and_then(|v| v.as_str())
                .map(|t| t.eq_ignore_ascii_case("function"))
                .unwrap_or(false);
            is_function && map.get("function").is_none()
        }
        _ => false,
    }
}

fn first_tool_name(tools: &Value) -> Option<String> {
    tools.as_array()
        .and_then(|arr| arr.iter().filter_map(|tool| {
            tool.get("function")
                .and_then(|f| f.get("name"))
                .and_then(|n| n.as_str())
                .map(|s| s.to_string())
        }).next())
}

fn build_tool_calls(tool_name: &str, args: Value, call_id: &str) -> Value {
    json!([
        {
            "id": call_id,
            "type": "function",
            "function": {
                "name": tool_name,
                "arguments": args
            }
        }
    ])
}

#[cfg(feature = "model")]
fn parse_escape_args(args_text: &str) -> Value {
    let mut map = serde_json::Map::new();
    let mut rest = args_text.trim();
    let escape = "<escape>";
    while let Some(key_end) = rest.find(":<escape>") {
        let key = rest[..key_end].trim();
        let val_start = key_end + ":<escape>".len();
        let remainder = &rest[val_start..];
        let val_end = remainder.find(escape).unwrap_or(remainder.len());
        let raw_val = remainder[..val_end].trim();
        let value = if raw_val.eq_ignore_ascii_case("true") {
            Value::Bool(true)
        } else if raw_val.eq_ignore_ascii_case("false") {
            Value::Bool(false)
        } else if let Ok(n) = raw_val.parse::<i64>() {
            Value::Number(n.into())
        } else if let Ok(n) = raw_val.parse::<f64>() {
            Value::Number(serde_json::Number::from_f64(n).unwrap())
        } else {
            Value::String(raw_val.to_string())
        };
        map.insert(key.to_string(), value);

        let next = &remainder[val_end + escape.len()..];
        rest = next.trim_start_matches(',').trim();
        if rest.is_empty() { break; }
    }
    Value::Object(map)
}

#[cfg(feature = "model")]
fn parse_function_call(output: &str) -> Option<(String, Value)> {
    let start_tag = "<start_function_call>call:";
    let end_tag = "<end_function_call>";
    let start = output.find(start_tag)?;
    let rest = &output[start + start_tag.len()..];
    let end = rest.find(end_tag)?;
    let body = &rest[..end];
    let name_end = body.find('{')?;
    let name = body[..name_end].trim();
    let args_text = body[name_end + 1..].trim().trim_end_matches('}');
    let args = if args_text.is_empty() { json!({}) } else { parse_escape_args(args_text) };
    Some((name.to_string(), args))
}

fn heuristic_route(req: &ChatCompletionRequest, prompt: &RouterPrompt) -> InferenceResult {
    let mut tool_name: Option<String> = None;
    let mut tool_args: Value = json!({});
    let requires_tool = req.tool_choice.as_ref().map(tool_choice_requires_tool).unwrap_or(false);

    if let Some(choice) = req.tool_choice.as_ref().and_then(resolve_tool_choice) {
        tool_name = Some(choice);
        tool_args = extract_args_from_text(&prompt.user_request).unwrap_or_else(|| json!({}));
    } else if let Some(tools) = req.tools.as_ref() {
        tool_name = select_tool_by_name(&prompt.user_request, tools);
        if tool_name.is_none() && requires_tool {
            tool_name = first_tool_name(tools);
        }
        tool_args = extract_args_from_text(&prompt.user_request).unwrap_or_else(|| json!({}));
    }

    if let Some(name) = tool_name {
        let calls = build_tool_calls(&name, tool_args, "call_heuristic");
        InferenceResult { content: None, tool_calls: Some(calls) }
    } else {
        InferenceResult { content: Some("NO_TOOL".to_string()), tool_calls: None }
    }
}

#[cfg(feature = "model")]
fn custom_load(varmap: &VarMap, path: &std::path::Path) -> anyhow::Result<()> {
    let st = unsafe { candle_core::safetensors::MmapedSafetensors::new(path)? };
    let st_names: std::collections::HashSet<String> = st.tensors().iter().map(|(n, _)| n.clone()).collect();

    let data = varmap.data().lock().unwrap();
    for (name, var) in data.iter() {
        if st_names.contains(name) {
            let st_tensor = st.load(name, &var.device())?;
            var.set(&st_tensor)?;
        }
    }
    Ok(())
}

#[cfg(feature = "model")]
fn render_prompt(messages: &[Message], tools: &Value) -> anyhow::Result<String> {
    let messages_value = serde_json::to_value(messages)?;
    let context = json!({
        "messages": messages_value,
        "tools": tools,
        "add_generation_prompt": true
    });

    let model_id = env::var("PCAI_ROUTER_MODEL_PATH")
        .unwrap_or_else(|_| default_model());
    let model_path = model_support::resolve_model_path(&model_id)?;
    let assets = model_support::ModelAssets::load(&model_path)?;
    assets.render_chat(&context)
}

#[cfg(feature = "model")]
#[derive(Debug, Clone)]
struct LoraInfo {
    path: PathBuf,
    r: usize,
}

#[cfg(feature = "model")]
fn read_lora_r(config_path: &Path) -> Option<usize> {
    let contents = fs::read_to_string(config_path).ok()?;
    let val = serde_json::from_str::<Value>(&contents).ok()?;
    val.get("r").and_then(|v| v.as_u64()).map(|v| v as usize)
}

#[cfg(feature = "model")]
fn infer_lora_r_from_weights(path: &Path) -> Option<usize> {
    let data = fs::read(path).ok()?;
    let tensors = safetensors::SafeTensors::deserialize(&data).ok()?;
    for name in tensors.names() {
        if name.contains("lora_a") {
            if let Ok(info) = tensors.tensor(&name) {
                let shape = info.shape();
                if let Some(first) = shape.first() {
                    return Some(*first as usize);
                }
            }
        }
    }
    None
}

#[cfg(feature = "model")]
fn resolve_lora_from_path(path: PathBuf) -> Option<LoraInfo> {
    let (weights_path, config_path) = if path.is_dir() {
        (path.join("adapter_model.safetensors"), path.join("adapter_config.json"))
    } else {
        let config_path = path.parent().unwrap_or(Path::new(".")).join("adapter_config.json");
        (path, config_path)
    };

    if !weights_path.exists() {
        return None;
    }

    let r = read_lora_r(&config_path)
        .or_else(|| infer_lora_r_from_weights(&weights_path))
        .unwrap_or(0);

    if r == 0 {
        return None;
    }

    Some(LoraInfo { path: weights_path, r })
}

#[cfg(feature = "model")]
fn resolve_lora_adapter(model_path: &Path) -> Option<LoraInfo> {
    if let Ok(path) = env::var("PCAI_ROUTER_LORA_PATH") {
        if let Some(info) = resolve_lora_from_path(PathBuf::from(path)) {
            return Some(info);
        }
    }

    let candidate = model_path.join("adapter_model.safetensors");
    if candidate.exists() {
        return resolve_lora_from_path(candidate);
    }

    None
}

#[cfg(feature = "model")]
fn lora_metadata() -> Option<LoraMetadata> {
    let from_env = env::var("PCAI_ROUTER_LORA_PATH").ok().map(PathBuf::from);
    let from_model = env::var("PCAI_ROUTER_MODEL_PATH").ok().map(|p| PathBuf::from(p).join("adapter_model.safetensors"));
    let candidate = from_env.or(from_model)?;
    let info = resolve_lora_from_path(candidate)?;
    Some(LoraMetadata { path: info.path.to_string_lossy().to_string(), r: info.r })
}

#[cfg(feature = "model")]
fn normalize_device_label(raw: &str) -> String {
    let lower = raw.trim().to_lowercase();
    if lower == "cpu" {
        return "cpu".to_string();
    }
    if lower == "cuda" || lower == "gpu" {
        return "cuda:0".to_string();
    }
    if let Some(rest) = lower.strip_prefix("cuda:") {
        return format!("cuda:{}", rest.trim());
    }
    if let Some(rest) = lower.strip_prefix("gpu:") {
        return format!("cuda:{}", rest.trim());
    }
    lower
}

#[cfg(feature = "model")]
fn device_label() -> String {
    if let Ok(device) = env::var("PCAI_ROUTER_DEVICE") {
        return normalize_device_label(&device);
    }
    if let Ok(gpu) = env::var("PCAI_ROUTER_GPU") {
        return format!("cuda:{}", gpu.trim());
    }
    "auto".to_string()
}

#[cfg(feature = "model")]
fn resolve_device() -> Device {
    if let Ok(device) = env::var("PCAI_ROUTER_DEVICE") {
        let normalized = normalize_device_label(&device);
        if normalized == "cpu" {
            return Device::Cpu;
        }
        if let Some(rest) = normalized.strip_prefix("cuda:") {
            if let Ok(idx) = rest.trim().parse::<usize>() {
                if let Ok(dev) = Device::new_cuda(idx) {
                    return dev;
                }
            }
        }
    }

    if let Ok(gpu) = env::var("PCAI_ROUTER_GPU") {
        if let Ok(idx) = gpu.trim().parse::<usize>() {
            if let Ok(dev) = Device::new_cuda(idx) {
                return dev;
            }
        }
    }

    Device::new_cuda(0).unwrap_or(Device::Cpu)
}

#[cfg(feature = "model")]
fn infer_with_model(req: &ChatCompletionRequest) -> anyhow::Result<InferenceResult> {
    let model_id = env::var("PCAI_ROUTER_MODEL_PATH").unwrap_or_else(|_| default_model());
    let model_path = model_support::resolve_model_path(&model_id)?;
    let lora_info = resolve_lora_adapter(&model_path);
    let lora_r = lora_info.as_ref().map(|l| l.r).unwrap_or(0);

    let prompt = match req.tools.as_ref() {
        Some(tools) => render_prompt(&req.messages, tools)?,
        None => render_prompt(&req.messages, &json!([]))?,
    };

    let config_raw = std::fs::read_to_string(model_path.join("config.json"))?;
    let config: Config = serde_json::from_str(&config_raw)?;

    let device = resolve_device();
    let model_file = model_path.join("model.safetensors");
    let mut tie_embeddings = true;
    if model_file.exists() {
        let st = unsafe { candle_core::safetensors::MmapedSafetensors::new(&model_file)? };
        tie_embeddings = !st.tensors().iter().any(|(name, _)| name == "lm_head.weight");
    }

    let varmap = VarMap::new();
    let vb = VarBuilder::from_varmap(&varmap, DType::BF16, &device);
    let model = Model::new(&config, lora_r, vb, tie_embeddings)?;
    if model_file.exists() {
        custom_load(&varmap, &model_file)?;
    }
    if let Some(lora) = lora_info {
        custom_load(&varmap, &lora.path)?;
    }

    let tokenizer = Tokenizer::from_file(model_path.join("tokenizer.json")).map_err(anyhow::Error::msg)?;
    let encoding = tokenizer.encode(prompt, true).map_err(anyhow::Error::msg)?;
    let input_tensor = Tensor::new(encoding.get_ids(), &device)?.unsqueeze(0)?;

    let max_tokens = req.max_tokens.unwrap_or(64) as usize;
    let output_ids = if use_kv_cache() {
        model.generate_with_cache(&input_tensor, max_tokens, &device)?
    } else {
        model.generate(&input_tensor, max_tokens, &device)?
    };
    let output_text = tokenizer.decode(&output_ids, true).map_err(anyhow::Error::msg)?;

    if let Some((name, args)) = parse_function_call(&output_text) {
        let calls = build_tool_calls(&name, args, "call_model");
        return Ok(InferenceResult { content: None, tool_calls: Some(calls) });
    }

    if output_text.contains("NO_TOOL") {
        Ok(InferenceResult { content: Some("NO_TOOL".to_string()), tool_calls: None })
    } else {
        Ok(InferenceResult { content: Some(output_text), tool_calls: None })
    }
}

pub fn build_router() -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v1/models", get(list_models))
        .route("/v1/chat/completions", post(chat))
}

fn estimate_tokens(text: &str) -> u32 {
    // Simple estimation: ~4 chars per token for English
    (text.len() as u32 / 4).max(1)
}

fn validate_request(req: &ChatCompletionRequest) -> Result<(), ErrorResponse> {
    if req.messages.is_empty() {
        return Err(ErrorResponse::bad_request(
            "messages array is required and must not be empty",
            Some("messages".to_string()),
        ));
    }

    // Validate message roles
    let valid_roles = ["user", "assistant", "system", "tool", "developer"];
    for (i, msg) in req.messages.iter().enumerate() {
        if !valid_roles.contains(&msg.role.as_str()) {
            return Err(ErrorResponse::bad_request(
                format!("Invalid role '{}' at messages[{}]. Must be one of: user, assistant, system, tool, developer", msg.role, i),
                Some(format!("messages[{}].role", i)),
            ));
        }
    }

    // Validate tool_choice if present
    if let Some(tc) = &req.tool_choice {
        match tc {
            Value::String(s) if s != "none" && s != "auto" && s != "required" => {
                return Err(ErrorResponse::bad_request(
                    format!("Invalid tool_choice value '{}'. Must be 'none', 'auto', 'required', or an object", s),
                    Some("tool_choice".to_string()),
                ));
            }
            Value::Object(map) => {
                if !map.contains_key("function") && !map.contains_key("type") {
                    return Err(ErrorResponse::bad_request(
                        "tool_choice object must have 'function' or 'type' field",
                        Some("tool_choice".to_string()),
                    ));
                }
            }
            _ => {}
        }
    }

    Ok(())
}

async fn chat(Json(req): Json<ChatCompletionRequest>) -> Result<Json<ChatCompletionResponse>, ErrorResponse> {
    // Validate request
    validate_request(&req)?;

    let model = req.model.clone().unwrap_or_else(default_model);
    let created = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    let message_text = last_user_message(&req.messages).unwrap_or_default();
    let prompt = parse_router_prompt(message_text);

    // Estimate prompt tokens
    let prompt_tokens = req.messages.iter()
        .filter_map(|m| m.content.as_ref())
        .map(|c| estimate_tokens(c))
        .sum::<u32>();

    let result = match router_engine() {
        RouterEngine::Heuristic => heuristic_route(&req, &prompt),
        RouterEngine::Model => {
            #[cfg(feature = "model")]
            {
                match infer_with_model(&req) {
                    Ok(res) => res,
                    Err(err) => {
                        tracing::warn!("model inference failed, falling back to heuristic: {err}");
                        heuristic_route(&req, &prompt)
                    }
                }
            }
            #[cfg(not(feature = "model"))]
            {
                tracing::warn!("model engine requested but runtime built without model feature; using heuristic");
                heuristic_route(&req, &prompt)
            }
        }
    };

    // Determine finish_reason based on whether tool was called
    let finish_reason = if result.tool_calls.is_some() {
        "tool_calls".to_string()
    } else {
        "stop".to_string()
    };

    // Estimate completion tokens
    let completion_tokens = result.content.as_ref().map(|c| estimate_tokens(c)).unwrap_or(0)
        + result.tool_calls.as_ref().map(|tc| estimate_tokens(&tc.to_string())).unwrap_or(0);

    let message = Message {
        role: "assistant".to_string(),
        content: result.content,
        tool_calls: result.tool_calls,
    };

    Ok(Json(ChatCompletionResponse {
        id: format!("pcai-router-{}", created),
        object: "chat.completion".to_string(),
        created,
        model,
        choices: vec![Choice {
            index: 0,
            message,
            finish_reason,
        }],
        usage: Some(Usage {
            prompt_tokens,
            completion_tokens,
            total_tokens: prompt_tokens + completion_tokens,
        }),
    }))
}

pub async fn serve(addr: SocketAddr) -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let app = build_router();
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;
    Ok(())
}
