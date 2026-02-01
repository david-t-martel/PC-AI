use anyhow::{Result, Context};
use candle_core::{Device, Tensor};
use memmap2::Mmap;
use serde::{Deserialize, Serialize};
use std::fs::File;
use std::io::{BufRead, BufReader, BufWriter, Write};
use std::path::Path;
use tokenizers::Tokenizer;
use crate::data_gen::TrainingItem;

pub struct Dataset {
    pub items: Vec<TrainingItem>,
    pub token_cache: Option<TokenCache>,
}

#[derive(Debug, Serialize, Deserialize, Clone)]
pub struct TokenCacheEntry {
    pub offset: u64,
    pub len: u32,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct TokenCacheMeta {
    pub source_jsonl: String,
    pub tokenizer_path: String,
    pub item_count: usize,
}

pub struct TokenCache {
    mmap: Mmap,
    entries: Vec<TokenCacheEntry>,
    mask_mmap: Option<Mmap>,
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
        Ok(Dataset { items, token_cache: None })
    }

    pub fn len(&self) -> usize {
        if let Some(cache) = &self.token_cache {
            cache.entries.len()
        } else {
            self.items.len()
        }
    }

    pub fn load_cached(cache_dir: &Path) -> Result<Self> {
        let cache = TokenCache::load(cache_dir)?;
        Ok(Dataset { items: Vec::new(), token_cache: Some(cache) })
    }

    pub fn build_token_cache(
        input_jsonl: &Path,
        tokenizer: &Tokenizer,
        tokenizer_path: &Path,
        output_dir: &Path,
    ) -> Result<TokenCacheMeta> {
        std::fs::create_dir_all(output_dir)?;
        let bin_path = output_dir.join("tokens.bin");
        let mask_path = output_dir.join("tokens.mask.bin");
        let idx_path = output_dir.join("tokens.idx.json");
        let meta_path = output_dir.join("tokens.meta.json");

        let file = File::open(input_jsonl)?;
        let reader = BufReader::new(file);
        let mut writer = BufWriter::new(File::create(&bin_path)?);
        let mut mask_writer = BufWriter::new(File::create(&mask_path)?);
        let mut entries = Vec::new();
        let mut offset: u64 = 0;

        for line in reader.lines() {
            let line = line?;
            if line.trim().is_empty() { continue; }
            let item: TrainingItem = serde_json::from_str(&line)?;
            let (ids, mask) = encode_item_with_mask(&item, tokenizer)?;
            for id in ids {
                writer.write_all(&id.to_le_bytes())?;
            }
            mask_writer.write_all(&mask)?;
            let len = ids.len() as u32;
            entries.push(TokenCacheEntry { offset, len });
            offset += len as u64;
        }
        writer.flush()?;
        mask_writer.flush()?;

        std::fs::write(&idx_path, serde_json::to_string_pretty(&entries)?)?;

        let meta = TokenCacheMeta {
            source_jsonl: input_jsonl.display().to_string(),
            tokenizer_path: tokenizer_path.display().to_string(),
            item_count: entries.len(),
        };
        std::fs::write(&meta_path, serde_json::to_string_pretty(&meta)?)?;
        Ok(meta)
    }

    pub fn get_batch(
        &self,
        start_idx: usize,
        batch_size: usize,
        tokenizer: Option<&Tokenizer>,
        device: &Device,
        pack_sequences: bool,
        max_seq_len: Option<usize>,
        eos_token_id: u32,
    ) -> Result<(Tensor, Tensor, Tensor)> {
        let end_idx = (start_idx + batch_size).min(self.items.len());
        let mut input_ids_batch = Vec::new();
        let mut mask_batch = Vec::new();
        let mut max_len = 0;

        if let Some(cache) = &self.token_cache {
            let end_idx = (start_idx + batch_size).min(cache.entries.len());
            for i in start_idx..end_idx {
                let ids = cache.get_ids(i)?;
                let mask = cache.get_mask(i)?;
                max_len = max_len.max(ids.len());
                input_ids_batch.push(ids);
                mask_batch.push(mask);
            }
        } else {
            let tokenizer = tokenizer.context("Tokenizer required for non-cached dataset")?;
            for i in start_idx..end_idx {
                let item = &self.items[i];
                let (ids, mask) = encode_item_with_mask(item, tokenizer)?;

                max_len = max_len.max(ids.len());
                input_ids_batch.push(ids);
                mask_batch.push(mask);
            }
        }

        let mut sequences = if pack_sequences {
            let (seqs, masks) = pack_token_sequences_with_mask(
                input_ids_batch,
                mask_batch,
                max_seq_len.unwrap_or(max_len),
                eos_token_id,
            );
            mask_batch = masks;
            seqs
        } else {
            input_ids_batch
        };

        if let Some(cap) = max_seq_len {
            for (seq, mask) in sequences.iter_mut().zip(mask_batch.iter_mut()) {
                if seq.len() > cap {
                    seq.truncate(cap);
                    mask.truncate(cap);
                }
            }
        }

        if sequences.is_empty() {
            return Err(anyhow::anyhow!("Empty batch"));
        }

        max_len = sequences.iter().map(|s| s.len()).max().unwrap_or(0);
        if let Some(cap) = max_seq_len {
            max_len = max_len.min(cap);
        }

        // Simple alignment/padding
        let mut padded_inputs = Vec::new();
        let mut padded_targets = Vec::new();
        let mut padded_masks = Vec::new();

        for (ids, mask) in sequences.drain(..).zip(mask_batch.drain(..)) {
            let mut input = ids.clone();
            let mut target = ids.clone();
            let mut loss_mask = mask.clone();

            // For causal LM, we shift targets
            input.pop(); // Remove last for input
            target.remove(0); // Remove first for target
            loss_mask.remove(0); // Align mask to targets

            while input.len() < max_len.saturating_sub(1) {
                input.push(0); // Pad with 0
                target.push(0);
                loss_mask.push(0);
            }
            padded_inputs.push(Tensor::new(input, device)?);
            padded_targets.push(Tensor::new(target, device)?);
            padded_masks.push(Tensor::new(loss_mask, device)?);
        }

        let inputs = Tensor::stack(&padded_inputs, 0)?;
        let targets = Tensor::stack(&padded_targets, 0)?;
        let masks = Tensor::stack(&padded_masks, 0)?;
        Ok((inputs, targets, masks))
    }
}

fn format_message_as_text(msg: &crate::data_gen::Message) -> Result<String> {
    let mut text = String::new();
    text.push_str(&format!("<|start_header_id|>{}<|end_header_id|>\n\n", msg.role));
    if let Some(content) = &msg.content {
        text.push_str(content);
    }
    if let Some(tool_calls) = &msg.tool_calls {
        text.push_str("\n");
        text.push_str(&serde_json::to_string(tool_calls)?);
    }
    text.push_str("<|eot_id|>");
    Ok(text)
}

fn encode_item_with_mask(item: &TrainingItem, tokenizer: &Tokenizer) -> Result<(Vec<u32>, Vec<u8>)> {
    let mut raw_ids = Vec::new();
    let mut raw_mask = Vec::new();
    let mut full_text = String::new();
    for msg in &item.messages {
        let text = format_message_as_text(msg)?;
        let encoding = tokenizer.encode(text, false).map_err(anyhow::Error::msg)?;
        let msg_ids = encoding.get_ids();
        let trainable = matches!(msg.role.as_str(), "assistant" | "model");
        raw_ids.extend_from_slice(msg_ids);
        raw_mask.extend(std::iter::repeat(if trainable { 1u8 } else { 0u8 }).take(msg_ids.len()));
        full_text.push_str(&text);
    }

    let full_encoding = tokenizer.encode(full_text, true).map_err(anyhow::Error::msg)?;
    let full_ids = full_encoding.get_ids().to_vec();

    if full_ids.len() == raw_ids.len() {
        return Ok((raw_ids, raw_mask));
    }

    if let Some(start) = find_subslice(&full_ids, &raw_ids) {
        let mut mask = vec![0u8; full_ids.len()];
        mask[start..start + raw_mask.len()].copy_from_slice(&raw_mask);
        return Ok((full_ids, mask));
    }

    Ok((raw_ids, raw_mask))
}

fn find_subslice(haystack: &[u32], needle: &[u32]) -> Option<usize> {
    if needle.is_empty() || needle.len() > haystack.len() {
        return None;
    }
    for start in 0..=(haystack.len() - needle.len()) {
        if haystack[start..start + needle.len()] == *needle {
            return Some(start);
        }
    }
    None
}

fn pack_token_sequences_with_mask(
    mut sequences: Vec<Vec<u32>>,
    mut masks: Vec<Vec<u8>>,
    max_len: usize,
    eos_token_id: u32,
) -> (Vec<Vec<u32>>, Vec<Vec<u8>>) {
    let mut packed = Vec::new();
    let mut packed_masks = Vec::new();
    let mut current = Vec::new();
    let mut current_mask = Vec::new();

    for (seq, mask) in sequences.drain(..).zip(masks.drain(..)) {
        if seq.is_empty() {
            continue;
        }
        let extra = if current.is_empty() { seq.len() } else { seq.len() + 1 };
        if current.len() + extra > max_len && !current.is_empty() {
            packed.push(current);
            packed_masks.push(current_mask);
            current = Vec::new();
            current_mask = Vec::new();
        }
        if !current.is_empty() {
            current.push(eos_token_id);
            current_mask.push(0);
        }
        current.extend(seq);
        current_mask.extend(mask);
    }

    if !current.is_empty() {
        packed.push(current);
        packed_masks.push(current_mask);
    }
    (packed, packed_masks)
}

impl TokenCache {
    pub fn load(cache_dir: &Path) -> Result<Self> {
        let bin_path = cache_dir.join("tokens.bin");
        let mask_path = cache_dir.join("tokens.mask.bin");
        let idx_path = cache_dir.join("tokens.idx.json");

        let idx_raw = std::fs::read_to_string(&idx_path)?;
        let entries: Vec<TokenCacheEntry> = serde_json::from_str(&idx_raw)?;

        let file = File::open(&bin_path)?;
        let mmap = unsafe { Mmap::map(&file)? };
        let mask_mmap = if mask_path.exists() {
            let mask_file = File::open(&mask_path)?;
            Some(unsafe { Mmap::map(&mask_file)? })
        } else {
            None
        };

        Ok(Self { mmap, entries, mask_mmap })
    }

    pub fn get_ids(&self, index: usize) -> Result<Vec<u32>> {
        let entry = self.entries.get(index).context("Token cache index out of range")?;
        let start = (entry.offset * 4) as usize;
        let end = start + (entry.len as usize * 4);
        let bytes = self.mmap.get(start..end).context("Token cache slice out of range")?;
        let mut ids = Vec::with_capacity(entry.len as usize);
        for chunk in bytes.chunks_exact(4) {
            ids.push(u32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
        }
        Ok(ids)
    }

    pub fn get_mask(&self, index: usize) -> Result<Vec<u8>> {
        let entry = self.entries.get(index).context("Token cache index out of range")?;
        if let Some(mask_mmap) = &self.mask_mmap {
            let start = entry.offset as usize;
            let end = start + (entry.len as usize);
            let bytes = mask_mmap.get(start..end).context("Token cache mask slice out of range")?;
            Ok(bytes.to_vec())
        } else {
            Ok(vec![1u8; entry.len as usize])
        }
    }
}
