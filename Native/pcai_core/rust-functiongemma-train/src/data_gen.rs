use anyhow::{Result, Context};
use serde::{Deserialize, Serialize};
use serde_json::{Value, Map, json};
use std::fs;
use std::path::Path;
use crate::schema_utils::generate_arg_sets;

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct Message {
    pub role: String,
    pub content: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tool_calls: Option<Value>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TrainingItem {
    pub messages: Vec<Message>,
    pub tools: Value,
}

impl TrainingItem {
    pub fn to_prompt(&self) -> String {
        let mut prompt = String::new();
        for msg in &self.messages {
            if msg.role == "user" {
                prompt.push_str("<user>\n");
                if let Some(c) = &msg.content {
                    prompt.push_str(c);
                }
                prompt.push_str("\n");
            } else if msg.role == "assistant" || msg.role == "model" {
                prompt.push_str("<assistant>\n");
                if let Some(c) = &msg.content {
                    prompt.push_str(c);
                }
                if let Some(t) = &msg.tool_calls {
                   prompt.push_str(&serde_json::to_string(t).unwrap_or_default());
                }
                prompt.push_str("\n");
            }
        }
        prompt
    }
}

#[derive(Debug, Deserialize, Clone)]
pub struct Scenario {
    pub mode: String,
    pub user_content: String,
    pub tool_name: Option<String>,
    #[serde(default)]
    pub tool_arguments: Map<String, Value>,
    pub assistant_content: Option<String>,
}

pub struct DataGenerator {
    tools: Value,
    default_system_msg: String,
}

impl DataGenerator {
    pub fn new(tools_path: &Path, system_prompt_path: Option<&Path>) -> Result<Self> {
        let tools_raw = fs::read_to_string(tools_path).context("Failed to read tools path")?;
        let tools_json: Value = serde_json::from_str(&tools_raw).context("Failed to parse tools JSON")?;
        let tools = tools_json.get("tools").cloned().unwrap_or(json!([]));

        let mut default_system_msg = "You are a model that can do function calling with the following functions".to_string();
        if let Some(p) = system_prompt_path {
            if p.exists() {
                let text = fs::read_to_string(p)?;
                default_system_msg = format!("{}\n\nYou are a tool-calling router. Use only the provided tools.", text);
            }
        }

        Ok(Self { tools, default_system_msg })
    }

    pub fn generate_from_schema(&self, max_cases: usize) -> Result<Vec<TrainingItem>> {
        let mut items = Vec::new();
        let tools_arr = self.tools.as_array().context("Tools is not an array")?;

        for tool in tools_arr {
            let fn_obj = tool.get("function").context("Tool has no function object")?;
            let name = fn_obj.get("name").and_then(|v| v.as_str()).context("Tool has no name")?;
            let description = fn_obj.get("description").and_then(|v| v.as_str()).unwrap_or("");
            let params = fn_obj.get("parameters").and_then(|v| v.as_object()).context("Tool has no parameters")?;

            for args in generate_arg_sets(params, max_cases) {
                let args_text = serde_json::to_string(&args)?;
                let user_prompt = format!("Use {} to perform the task: {}. Arguments: {}", name, description, args_text);

                let context_aware_prompt = format!(
                    "[NATIVE_CONTEXT]\n{{\"telemetry\": \"active\", \"tool\": \"{}\"}}\n\n[USER_REQUEST]\n{}",
                    name, user_prompt
                );

                let thought_process = format!(
                    "<thought>\nUser request: \"{}\".\nReasoning: Tool '{}' performs \"{}\".\nDecision: I will call '{}' to satisfy the request.\n</thought>\n",
                    user_prompt, name, description, name
                );

                items.push(TrainingItem {
                    messages: vec![
                        Message {
                            role: "user".to_string(),
                            content: Some(format!("{}\n\n{}", self.default_system_msg, context_aware_prompt)),
                            tool_calls: None,
                        },
                        Message {
                            role: "assistant".to_string(),
                            content: Some(thought_process),
                            tool_calls: Some(json!([
                                {
                                    "type": "function",
                                    "function": {
                                        "name": name,
                                        "arguments": args,
                                    }
                                }
                            ])),
                        },
                    ],
                    tools: self.tools.clone(),
                });
            }
        }

        // Add negative cases
        let negative_items = crate::schema_utils::generate_negative_cases(&self.tools);
        items.extend(negative_items);

        Ok(items)
    }

    pub fn generate_from_scenarios(&self, scenarios_path: &Path) -> Result<Vec<TrainingItem>> {
        let raw = fs::read_to_string(scenarios_path)?;
        let scenarios_val: Value = serde_json::from_str(&raw)?;

        let items_val = if scenarios_val.is_array() {
            scenarios_val.as_array().unwrap().clone()
        } else {
            scenarios_val.get("scenarios").and_then(|v| v.as_array()).cloned().unwrap_or_default()
        };

        let mut items = Vec::new();
        for val in items_val {
            let scenario: Scenario = serde_json::from_value(val)?;
            if scenario.tool_name.is_some() {
                continue; // Covered by schema gen or requires custom handling
            }

            items.push(TrainingItem {
                messages: vec![
                    Message {
                        role: "user".to_string(),
                        content: Some(format!("{}\n\n{}", self.default_system_msg, scenario.user_content)),
                        tool_calls: None,
                    },
                    Message {
                        role: "assistant".to_string(),
                        content: Some(scenario.assistant_content.unwrap_or_else(|| "NO_TOOL".to_string())),
                        tool_calls: None,
                    },
                ],
                tools: self.tools.clone(),
            });
        }
        Ok(items)
    }
}
