use anyhow::{Result, Context};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use crate::data_gen::TrainingItem;

#[derive(Debug, Default, Serialize, Deserialize)]
pub struct EvaluationMetrics {
    pub total: usize,
    pub tool_name_correct: usize,
    pub arg_exact_match: usize,
    pub no_tool_correct: usize,
    pub schema_failures: usize,
}

impl EvaluationMetrics {
    pub fn tool_accuracy(&self) -> f64 {
        if self.total == 0 { 0.0 } else { self.tool_name_correct as f64 / self.total as f64 }
    }
    pub fn arg_accuracy(&self) -> f64 {
        if self.total == 0 { 0.0 } else { self.arg_exact_match as f64 / self.total as f64 }
    }
}

#[derive(Debug)]
pub struct EvalSampleResult {
    pub tool_match: bool,
    pub arg_match: bool,
    pub no_tool_match: bool,
    pub schema_valid: bool,
}

pub fn evaluate_sample(
    output: &str,
    expected: &TrainingItem,
    fast_eval: bool,
    schema_validate: bool,
) -> Result<EvalSampleResult> {
    let expected_assistant = expected.messages.iter()
        .find(|m| m.role == "assistant")
        .context("No assistant message in expected item")?;

    let expected_tool = extract_expected_tool(expected_assistant.tool_calls.as_ref());
    let parsed_tool = parse_tool_call(output).and_then(extract_parsed_tool);

    let mut tool_match = false;
    let mut arg_match = false;
    let mut no_tool_match = false;
    let mut schema_valid = true;

    match (expected_tool, parsed_tool) {
        (Some((exp_name, exp_args)), Some((act_name, act_args))) => {
            tool_match = exp_name == act_name;
            if tool_match {
                arg_match = exp_args == act_args;
            }
            if schema_validate {
                schema_valid = validate_tool_call_schema(&act_name, &act_args, &expected.tools)?;
            }
        }
        (None, Some((_act_name, act_args))) => {
            no_tool_match = false;
            if schema_validate {
                schema_valid = validate_tool_call_schema_from_any(&act_args, &expected.tools)?;
            }
        }
        (Some(_), None) => {
            tool_match = false;
            arg_match = false;
            no_tool_match = false;
        }
        (None, None) => {
            no_tool_match = output.contains("NO_TOOL") || !output.contains("\"type\": \"function\"");
        }
    }

    if fast_eval {
        arg_match = tool_match;
    }

    Ok(EvalSampleResult {
        tool_match,
        arg_match,
        no_tool_match,
        schema_valid,
    })
}

pub fn parse_tool_call(output: &str) -> Option<Value> {
    // Attempt to find JSON array or object in output
    let start = output.find('[').or_else(|| output.find('{'))?;
    let end = output.rfind(']').or_else(|| output.rfind('}'))?;

    if end > start {
        serde_json::from_str(&output[start..=end]).ok()
    } else {
        None
    }
}

fn extract_expected_tool(tool_calls: Option<&Value>) -> Option<(String, Value)> {
    let tool_calls = tool_calls?.as_array()?;
    let tc = tool_calls.get(0)?;
    let func = tc.get("function")?;
    let name = func.get("name")?.as_str()?.to_string();
    let args = func.get("arguments").cloned().unwrap_or(Value::Object(Default::default()));
    Some((name, args))
}

fn extract_parsed_tool(value: Value) -> Option<(String, Value)> {
    if value.is_array() {
        let arr = value.as_array()?;
        let tc = arr.get(0)?;
        let func = tc.get("function")?;
        let name = func.get("name")?.as_str()?.to_string();
        let args = func.get("arguments").cloned().unwrap_or(Value::Object(Default::default()));
        Some((name, args))
    } else if value.is_object() {
        let func = value.get("function")?;
        let name = func.get("name")?.as_str()?.to_string();
        let args = func.get("arguments").cloned().unwrap_or(Value::Object(Default::default()));
        Some((name, args))
    } else {
        None
    }
}

fn validate_tool_call_schema(tool_name: &str, args: &Value, tools: &Value) -> Result<bool> {
    let tools_arr = match tools.as_array() {
        Some(arr) => arr,
        None => return Ok(false),
    };
    for tool in tools_arr {
        let func = tool.get("function").context("Tool missing function")?;
        let name = func.get("name").and_then(|v| v.as_str()).unwrap_or("");
        if name != tool_name {
            continue;
        }
        let params = match func.get("parameters").and_then(|v| v.as_object()) {
            Some(p) => p,
            None => return Ok(false),
        };
        return Ok(validate_args_against_schema(args, params));
    }
    Ok(false)
}

fn validate_tool_call_schema_from_any(args: &Value, tools: &Value) -> Result<bool> {
    let tools_arr = match tools.as_array() {
        Some(arr) => arr,
        None => return Ok(false),
    };
    for tool in tools_arr {
        let func = tool.get("function").context("Tool missing function")?;
        let params = match func.get("parameters").and_then(|v| v.as_object()) {
            Some(p) => p,
            None => continue,
        };
        if validate_args_against_schema(args, params) {
            return Ok(true);
        }
    }
    Ok(false)
}

fn validate_args_against_schema(args: &Value, params: &serde_json::Map<String, Value>) -> bool {
    let arg_obj = match args.as_object() {
        Some(obj) => obj,
        None => return false,
    };
    let required: Vec<String> = params.get("required")
        .and_then(|v| v.as_array())
        .map(|arr| arr.iter().filter_map(|v| v.as_str().map(|s| s.to_string())).collect())
        .unwrap_or_default();
    for req in required {
        if !arg_obj.contains_key(&req) {
            return false;
        }
    }
    let props = match params.get("properties").and_then(|v| v.as_object()) {
        Some(p) => p,
        None => return true,
    };
    for (key, val) in arg_obj {
        if let Some(schema) = props.get(key) {
            if !validate_value(schema, val) {
                return false;
            }
        }
    }
    true
}

fn validate_value(schema: &Value, val: &Value) -> bool {
    if let Some(enum_vals) = schema.get("enum").and_then(|v| v.as_array()) {
        return enum_vals.iter().any(|v| v == val);
    }
    let typ = schema.get("type").and_then(|v| v.as_str()).unwrap_or("string");
    match typ {
        "string" => val.is_string(),
        "boolean" => val.is_boolean(),
        "integer" => val.as_i64().is_some(),
        "number" => val.as_f64().is_some(),
        "array" => val.is_array(),
        "object" => val.is_object(),
        _ => true,
    }
}
