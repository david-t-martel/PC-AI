use anyhow::{Result, Context};
use serde_json::{Value, json};
use crate::data_gen::TrainingItem;

pub struct EvaluationResult {
    pub total: usize,
    pub correct: usize,
    pub schema_failures: usize,
}

impl EvaluationResult {
    pub fn accuracy(&self) -> f64 {
        if self.total == 0 { 0.0 } else { (self.correct as f64) / (self.total as f64) }
    }
}

pub fn evaluate_output(output: &str, expected: &TrainingItem) -> Result<bool> {
    // 1. Extract thought and tool calls from output
    // Standard FunctionGemma output is often: <thought>...</thought>
    // And potentially a tool call JSON or just text.

    // Simple verification: Does it contain the expected tool name if one is expected?
    let expected_assistant = expected.messages.iter()
        .find(|m| m.role == "assistant")
        .context("No assistant message in expected item")?;

    if let Some(expected_tool_calls) = &expected_assistant.tool_calls {
        let expected_tc = expected_tool_calls.as_array()
            .and_then(|a| a.get(0))
            .and_then(|o| o.get("function"))
            .and_then(|f| f.get("name"))
            .and_then(|n| n.as_str())
            .context("Invalid expected tool call format")?;

        // Check if the output contains the tool call JSON or at least the tool name
        // Real implementation should parse the JSON strictly.
        if output.contains(expected_tc) {
            // Further check arguments
            return Ok(true);
        }
    } else {
        // Expected NO_TOOL
        if output.contains("NO_TOOL") || !output.contains("\"type\": \"function\"") {
            return Ok(true);
        }
    }

    Ok(false)
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
