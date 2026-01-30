use anyhow::Result;
use candle_core::Device;
use candle_nn::{Optimizer, VarMap};
use crate::model::{Model, Config};
use crate::dataset::Dataset;
use tokenizers::Tokenizer;
use crate::scheduler::{LRScheduler, SchedulerConfig, SchedulerType};
use crate::checkpoint::{Checkpoint, CheckpointConfig};
use std::path::PathBuf;

pub struct TrainerConfig {
    pub lr: f64,
    pub epochs: usize,
    pub batch_size: usize,
    pub grad_accum: usize,
    pub lora_r: usize,
    pub lora_alpha: f64,
    pub lora_dropout: f64,
    pub pack_sequences: bool,
    pub max_seq_len: Option<usize>,
    pub eos_token_id: u32,
    pub use_lora: bool,
    pub warmup_steps: usize,
    pub scheduler_type: String,
}

impl Default for TrainerConfig {
    fn default() -> Self {
        Self {
            lr: 1e-4,
            epochs: 3,
            batch_size: 4,
            grad_accum: 4,
            lora_r: 8,
            lora_alpha: 16.0,
            lora_dropout: 0.0,
            pack_sequences: true,
            max_seq_len: Some(512),
            eos_token_id: 2,
            use_lora: true,
            warmup_steps: 100,
            scheduler_type: "cosine".to_string(),
        }
    }
}

pub struct Trainer<'a> {
    pub model: Model,
    pub config: &'a Config,
    pub trainer_cfg: TrainerConfig,
    pub device: Device,
    pub varmap: VarMap,
    pub scheduler: LRScheduler,
    pub checkpoint_config: CheckpointConfig,
    pub global_step: usize,
}

impl<'a> Trainer<'a> {
    pub fn new(model: Model, config: &'a Config, trainer_cfg: TrainerConfig, device: Device, varmap: VarMap) -> Self {
        let scheduler_type = match trainer_cfg.scheduler_type.as_str() {
            "linear" => SchedulerType::Linear,
            "constant" => SchedulerType::Constant,
            _ => SchedulerType::Cosine,
        };

        // Initialize scheduler with placeholder total_steps (will be updated in train())
        let scheduler = LRScheduler::new(SchedulerConfig {
            scheduler_type,
            warmup_steps: trainer_cfg.warmup_steps,
            total_steps: trainer_cfg.epochs * 1000, // Placeholder, updated in train()
            min_lr: trainer_cfg.lr / 10.0,
            max_lr: trainer_cfg.lr,
        });

        let checkpoint_config = CheckpointConfig {
            output_dir: PathBuf::from("./checkpoints"),
            save_every_n_steps: 500,
            max_checkpoints: 3,
        };

        Self {
            model,
            config,
            trainer_cfg,
            device,
            varmap,
            scheduler,
            checkpoint_config,
            global_step: 0,
        }
    }

    pub fn train(&mut self, dataset: &Dataset, tokenizer: Option<&Tokenizer>) -> Result<()> {
        let num_batches = dataset.len() / self.trainer_cfg.batch_size;
        let total_steps = self.trainer_cfg.epochs * num_batches;

        // Update scheduler with correct total_steps
        let scheduler_type = match self.trainer_cfg.scheduler_type.as_str() {
            "linear" => SchedulerType::Linear,
            "constant" => SchedulerType::Constant,
            _ => SchedulerType::Cosine,
        };

        self.scheduler = LRScheduler::new(SchedulerConfig {
            scheduler_type,
            warmup_steps: self.trainer_cfg.warmup_steps,
            total_steps,
            min_lr: self.trainer_cfg.lr / 10.0,
            max_lr: self.trainer_cfg.lr,
        });

        let mut optimizer = candle_nn::AdamW::new_lr(self.varmap.all_vars(), self.trainer_cfg.lr)?;
        let mut best_loss = f64::MAX;

        for epoch in 0..self.trainer_cfg.epochs {
            println!("Epoch {}/{}", epoch + 1, self.trainer_cfg.epochs);
            let mut epoch_loss = 0.0;
            let mut batch_count = 0;

            for i in 0..num_batches {
                // Get current learning rate from scheduler
                let current_lr = self.scheduler.get_lr(self.global_step);

                // Recreate optimizer with new learning rate
                // Note: This is necessary because Candle doesn't support dynamic LR updates
                if self.global_step % self.trainer_cfg.grad_accum == 0 {
                    optimizer = candle_nn::AdamW::new_lr(self.varmap.all_vars(), current_lr)?;
                }

                let start_idx = i * self.trainer_cfg.batch_size;
                let (inputs, targets) = dataset.get_batch(
                    start_idx,
                    self.trainer_cfg.batch_size,
                    tokenizer,
                    &self.device,
                    self.trainer_cfg.pack_sequences,
                    self.trainer_cfg.max_seq_len,
                    self.trainer_cfg.eos_token_id,
                )?;

                let logits = self.model.forward(&inputs)?;
                let (b, s, v) = logits.dims3()?;
                let logits_flat = logits.reshape((b * s, v))?.to_dtype(candle_core::DType::F32)?;
                let targets_flat = targets.reshape((b * s,))?;

                let loss = candle_nn::loss::cross_entropy(&logits_flat, &targets_flat)?;
                let loss_val = loss.to_scalar::<f32>()? as f64;

                epoch_loss += loss_val;
                batch_count += 1;

                // Scale loss for gradient accumulation
                let scaled_loss = loss.affine(1.0 / (self.trainer_cfg.grad_accum as f64), 0.0)?;
                optimizer.backward_step(&scaled_loss)?;

                if (i + 1) % self.trainer_cfg.grad_accum == 0 {
                    self.global_step += 1;

                    // Save checkpoint periodically
                    if self.global_step % self.checkpoint_config.save_every_n_steps == 0 {
                        self.save_checkpoint(epoch, best_loss)?;
                        Checkpoint::cleanup_old(&self.checkpoint_config)?;
                    }
                }

                if i % 10 == 0 {
                    println!(
                        "Batch {}/{}: Loss: {:.4}, LR: {:.2e}",
                        i, num_batches, loss_val, current_lr
                    );
                }
            }

            let avg_epoch_loss = epoch_loss / batch_count as f64;
            println!("Epoch {} completed. Avg Loss: {:.4}", epoch + 1, avg_epoch_loss);

            // Update best loss
            if avg_epoch_loss < best_loss {
                best_loss = avg_epoch_loss;
                println!("New best loss: {:.4}", best_loss);
            }
        }

        // Save final checkpoint
        self.save_checkpoint(self.trainer_cfg.epochs - 1, best_loss)?;
        println!("Training completed. Best loss: {:.4}", best_loss);

        Ok(())
    }

    pub fn save_adapters(&self, path: &std::path::Path) -> Result<()> {
        // Collect only lora tensors
        let mut lora_vars = std::collections::HashMap::new();
        for (name, var) in self.varmap.data().lock().unwrap().iter() {
            if name.contains("lora_a") || name.contains("lora_b") {
                lora_vars.insert(name.clone(), var.as_tensor().clone());
            }
        }

        candle_core::safetensors::save(&lora_vars, path)?;
        println!("Adapters saved to {:?}", path);
        Ok(())
    }

    pub fn save_peft_adapter(&self, output_path: &std::path::Path) -> Result<()> {
        use std::fs;

        fs::create_dir_all(output_path)?;

        // Collect LoRA tensors
        let mut lora_vars = std::collections::HashMap::new();
        for (name, var) in self.varmap.data().lock().unwrap().iter() {
            if name.contains("lora_a") || name.contains("lora_b") {
                lora_vars.insert(name.clone(), var.as_tensor().clone());
            }
        }

        // Save adapter weights as safetensors
        let weights_path = output_path.join("adapter_model.safetensors");
        candle_core::safetensors::save(&lora_vars, &weights_path)?;

        // Save adapter config (PEFT-compatible JSON)
        let adapter_config = serde_json::json!({
            "peft_type": "LORA",
            "base_model_name_or_path": "google/gemma-2-2b-it",
            "r": self.trainer_cfg.lora_r,
            "lora_alpha": self.trainer_cfg.lora_alpha,
            "lora_dropout": self.trainer_cfg.lora_dropout,
            "target_modules": ["q_proj", "k_proj", "v_proj", "o_proj"],
            "bias": "none",
            "task_type": "CAUSAL_LM"
        });

        let config_path = output_path.join("adapter_config.json");
        fs::write(&config_path, serde_json::to_string_pretty(&adapter_config)?)?;

        println!("PEFT adapter saved to {:?}", output_path);
        Ok(())
    }

    /// Save checkpoint to disk
    fn save_checkpoint(&self, epoch: usize, best_loss: f64) -> Result<()> {
        use std::fs;

        let checkpoint_dir = self.checkpoint_config.output_dir.join(format!("checkpoint-{}", self.global_step));
        fs::create_dir_all(&checkpoint_dir)?;

        // Save model weights (LoRA adapters)
        let weights_path = checkpoint_dir.join("adapter_model.safetensors");
        let mut lora_vars = std::collections::HashMap::new();
        for (name, var) in self.varmap.data().lock().unwrap().iter() {
            if name.contains("lora_a") || name.contains("lora_b") {
                lora_vars.insert(name.clone(), var.as_tensor().clone());
            }
        }
        candle_core::safetensors::save(&lora_vars, &weights_path)?;

        // Create checkpoint metadata
        let checkpoint = Checkpoint {
            epoch,
            global_step: self.global_step,
            best_loss,
            optimizer_state: vec![], // TODO: Save optimizer state if needed
            rng_state: None, // TODO: Save RNG state for reproducibility
        };

        checkpoint.save(&checkpoint_dir)?;
        println!("Checkpoint saved to {:?}", checkpoint_dir);

        Ok(())
    }

    /// Resume training from a checkpoint
    pub fn resume_from_checkpoint(&mut self, checkpoint_path: &std::path::Path) -> Result<()> {
        // Load checkpoint metadata
        let checkpoint = Checkpoint::load(checkpoint_path)?;
        self.global_step = checkpoint.global_step;

        println!("Resuming from checkpoint at step {}", self.global_step);
        println!("Previous best loss: {:.4}", checkpoint.best_loss);

        // Load model weights
        let weights_path = checkpoint_path.join("adapter_model.safetensors");
        if weights_path.exists() {
            let tensors = candle_core::safetensors::load(&weights_path, &self.device)?;

            // Update varmap with loaded tensors
            for (name, tensor) in tensors {
                if let Some(var) = self.varmap.data().lock().unwrap().get_mut(&name) {
                    var.set(&tensor)?;
                } else {
                    println!("Warning: Checkpoint contains tensor '{}' not found in model", name);
                }
            }

            println!("Loaded adapter weights from {:?}", weights_path);
        } else {
            println!("Warning: No adapter weights found at {:?}", weights_path);
        }

        Ok(())
    }
}
