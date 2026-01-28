use anyhow::{Result, Context};
use candle_core::{Device, Tensor};
use serde_json::Value;
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::path::Path;
use tokenizers::Tokenizer;
use crate::data_gen::TrainingItem;

pub struct Dataset {
    pub items: Vec<TrainingItem>,
}

impl Dataset {
    pub fn load(path: &Path) -> Result<Self> {
        let file = File::open(path)?;
        let reader = BufReader::new(file);
        let mut items = Vec::new();
        for line in reader.lines() {
            let line = line?;
            if line.trim().is_empty() { continue; }
            let item: TrainingItem = serde_json::from_str(&line)?;
            items.push(item);
        }
        Ok(Dataset { items })
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }

    pub fn get_batch(&self, start_idx: usize, batch_size: usize, tokenizer: &Tokenizer, device: &Device) -> Result<(Tensor, Tensor)> {
        let end_idx = (start_idx + batch_size).min(self.items.len());
        let mut input_ids_batch = Vec::new();
        let mut max_len = 0;

        for i in start_idx..end_idx {
            let item = &self.items[i];
            let text = format_item_as_text(item)?;
            let encoding = tokenizer.encode(text, true).map_err(anyhow::Error::msg)?;
            let ids = encoding.get_ids().to_vec();

            max_len = max_len.max(ids.len());
            input_ids_batch.push(ids);
        }

        // Simple alignment/padding
        let mut padded_inputs = Vec::new();
        let mut padded_targets = Vec::new();

        for ids in input_ids_batch {
            let mut input = ids.clone();
            let mut target = ids.clone();

            // For causal LM, we shift targets
            // In a real training loop, you might want to mask the user prompt in the loss
            input.pop(); // Remove last for input
            target.remove(0); // Remove first for target

            while input.len() < max_len - 1 {
                input.push(0); // Pad with 0
                target.push(0);
            }
            padded_inputs.push(Tensor::new(input, device)?);
            padded_targets.push(Tensor::new(target, device)?);
        }

        let inputs = Tensor::stack(&padded_inputs, 0)?;
        let targets = Tensor::stack(&padded_targets, 0)?;
        Ok((inputs, targets))
    }
}

fn format_item_as_text(item: &TrainingItem) -> Result<String> {
    // Basic Gemma 3 template implementation
    // <|begin_of_text|><|start_header_id|>user<|end_header_id|>\n\nPrompt<|eot_id|><|start_header_id|>assistant<|end_header_id|>\n\nResponse<|eot_id|>
    let mut text = String::new();
    for msg in &item.messages {
        text.push_str(&format!("<|start_header_id|>{}<|end_header_id|>\n\n", msg.role));
        if let Some(content) = &msg.content {
            text.push_str(content);
        }
        if let Some(tool_calls) = &msg.tool_calls {
            text.push_str("\n");
            text.push_str(&serde_json::to_string(tool_calls)?);
        }
        text.push_str("<|eot_id|>");
    }
    Ok(text)
}
