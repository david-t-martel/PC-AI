use serde_json::json;

#[tokio::test]
async fn health_and_models() {
    unsafe { std::env::set_var("PCAI_ROUTER_ENGINE", "heuristic"); }

    let app = rust_functiongemma_runtime::build_router();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let base = format!("http://{}", addr);
    let client = reqwest::Client::new();

    let health: serde_json::Value = client.get(format!("{}/health", base))
        .send().await.unwrap()
        .json().await.unwrap();
    assert_eq!(health["status"], "ok");
    assert!(health["metadata"]["version"].as_str().is_some());
    assert!(health["metadata"]["model"].as_str().is_some());
    assert!(health["metadata"]["tools"].is_object());

    let models: serde_json::Value = client.get(format!("{}/v1/models", base))
        .send().await.unwrap()
        .json().await.unwrap();
    assert_eq!(models["object"], "list");
    assert!(models["data"][0]["metadata"]["version"].as_str().is_some());
    assert!(models["data"][0]["metadata"]["model"].as_str().is_some());
    assert!(models["data"][0]["metadata"]["tools"].is_object());
}

#[tokio::test]
async fn chat_completion_tool_call() {
    unsafe { std::env::set_var("PCAI_ROUTER_ENGINE", "heuristic"); }

    let app = rust_functiongemma_runtime::build_router();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let base = format!("http://{}", addr);
    let client = reqwest::Client::new();

    let tools = json!([
        {
            "type": "function",
            "function": {
                "name": "SearchDocs",
                "description": "Search vendor documentation",
                "parameters": {
                    "type": "object",
                    "properties": {
                        "query": {"type": "string"}
                    },
                    "required": ["query"]
                }
            }
        }
    ]);

    let payload = json!({
        "model": "functiongemma-270m-it",
        "messages": [
            {"role": "user", "content": "Use SearchDocs to perform the task. Arguments: {\"query\":\"usb\"}"}
        ],
        "tools": tools,
        "tool_choice": "auto"
    });

    let resp: serde_json::Value = client.post(format!("{}/v1/chat/completions", base))
        .json(&payload)
        .send().await.unwrap()
        .json().await.unwrap();

    let tool_calls = &resp["choices"][0]["message"]["tool_calls"];
    assert!(tool_calls.is_array());
    let name = tool_calls[0]["function"]["name"].as_str().unwrap();
    assert_eq!(name, "SearchDocs");
}

#[tokio::test]
async fn chat_completion_no_tool() {
    unsafe { std::env::set_var("PCAI_ROUTER_ENGINE", "heuristic"); }

    let app = rust_functiongemma_runtime::build_router();
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    let base = format!("http://{}", addr);
    let client = reqwest::Client::new();

    let payload = json!({
        "model": "functiongemma-270m-it",
        "messages": [
            {"role": "user", "content": "Tell me a joke"}
        ],
        "tools": [],
        "tool_choice": "auto"
    });

    let resp: serde_json::Value = client.post(format!("{}/v1/chat/completions", base))
        .json(&payload)
        .send().await.unwrap()
        .json().await.unwrap();

    let content = resp["choices"][0]["message"]["content"].as_str().unwrap();
    assert_eq!(content, "NO_TOOL");
}
