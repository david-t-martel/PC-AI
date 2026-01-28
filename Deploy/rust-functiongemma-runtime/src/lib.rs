use axum::{routing::{get, post}, Json, Router};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::{env, net::SocketAddr, time::{SystemTime, UNIX_EPOCH}};
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
struct ChatCompletionResponse {
    id: String,
    object: String,
    created: u64,
    model: String,
    choices: Vec<Choice>,
}

#[derive(Debug, Serialize)]
struct ModelInfo {
    id: String,
    object: String,
}

#[derive(Debug, Serialize)]
struct ModelList {
    object: String,
    data: Vec<ModelInfo>,
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

fn router_engine() -> RouterEngine {
    match env::var("PCAI_ROUTER_ENGINE").unwrap_or_else(|_| "heuristic".to_string()).to_lowercase().as_str() {
        "model" => RouterEngine::Model,
        _ => RouterEngine::Heuristic,
    }
}

async fn health() -> Json<Value> {
    Json(json!({"status": "ok"}))
}

async fn list_models() -> Json<ModelList> {
    let model = default_model();
    Json(ModelList {
        object: "list".to_string(),
        data: vec![ModelInfo { id: model, object: "model".to_string() }],
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

    if let Some(choice) = req.tool_choice.as_ref().and_then(resolve_tool_choice) {
        tool_name = Some(choice);
        tool_args = extract_args_from_text(&prompt.user_request).unwrap_or_else(|| json!({}));
    } else if let Some(tools) = req.tools.as_ref() {
        tool_name = select_tool_by_name(&prompt.user_request, tools);
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
fn infer_with_model(req: &ChatCompletionRequest) -> anyhow::Result<InferenceResult> {
    let model_id = env::var("PCAI_ROUTER_MODEL_PATH").unwrap_or_else(|_| default_model());
    let model_path = model_support::resolve_model_path(&model_id)?;

    let prompt = match req.tools.as_ref() {
        Some(tools) => render_prompt(&req.messages, tools)?,
        None => render_prompt(&req.messages, &json!([]))?,
    };

    let config_raw = std::fs::read_to_string(model_path.join("config.json"))?;
    let config: Config = serde_json::from_str(&config_raw)?;

    let device = Device::new_cuda(0).unwrap_or(Device::Cpu);
    let model_file = model_path.join("model.safetensors");
    let mut tie_embeddings = true;
    if model_file.exists() {
        let st = unsafe { candle_core::safetensors::MmapedSafetensors::new(&model_file)? };
        tie_embeddings = !st.tensors().iter().any(|(name, _)| name == "lm_head.weight");
    }

    let varmap = VarMap::new();
    let vb = VarBuilder::from_varmap(&varmap, DType::BF16, &device);
    let model = Model::new(&config, 0, vb, tie_embeddings)?;
    if model_file.exists() {
        custom_load(&varmap, &model_file)?;
    }

    let tokenizer = Tokenizer::from_file(model_path.join("tokenizer.json")).map_err(anyhow::Error::msg)?;
    let encoding = tokenizer.encode(prompt, true).map_err(anyhow::Error::msg)?;
    let input_tensor = Tensor::new(encoding.get_ids(), &device)?.unsqueeze(0)?;

    let max_tokens = req.max_tokens.unwrap_or(64) as usize;
    let output_ids = model.generate(&input_tensor, max_tokens, &device)?;
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

async fn chat(Json(req): Json<ChatCompletionRequest>) -> Json<ChatCompletionResponse> {
    let model = req.model.clone().unwrap_or_else(default_model);
    let created = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    let message_text = last_user_message(&req.messages).unwrap_or_default();
    let prompt = parse_router_prompt(message_text);

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

    let message = Message {
        role: "assistant".to_string(),
        content: result.content,
        tool_calls: result.tool_calls,
    };

    Json(ChatCompletionResponse {
        id: format!("pcai-router-{}", created),
        object: "chat.completion".to_string(),
        created,
        model,
        choices: vec![Choice {
            index: 0,
            message,
            finish_reason: "stop".to_string(),
        }],
    })
}

pub async fn serve(addr: SocketAddr) -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .init();

    let app = build_router();
    axum::serve(tokio::net::TcpListener::bind(addr).await?, app).await?;
    Ok(())
}
