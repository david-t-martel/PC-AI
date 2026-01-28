use anyhow::Result;
use candle_core::{DType, Device, Tensor};
use candle_nn::{VarBuilder, VarMap};
use clap::{Parser, Subcommand};
use std::fs;
use std::path::PathBuf;
use tokenizers::Tokenizer;

use rust_functiongemma_train::{Config, Model};
use rust_functiongemma_train::data_gen::DataGenerator;
use rust_functiongemma_train::dataset::Dataset;
use rust_functiongemma_train::trainer::{Trainer, TrainerConfig};
use rust_functiongemma_train::eval::parse_tool_call;
use rust_functiongemma_train::router_dataset::{
    build_router_dataset,
    build_tool_test_vectors,
    write_jsonl,
    write_test_vectors,
    RouterDatasetConfig,
};

#[derive(Parser)]
#[command(author, version, about, long_about = None)]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Prepare training data from tool schema and scenarios
    Prepare {
        #[arg(long)]
        tools: String,
        #[arg(long)]
        output: String,
        #[arg(long)]
        scenarios: Option<String>,
        #[arg(long, default_value = "24")]
        max_cases: usize,
        #[arg(long)]
        system_prompt: Option<String>,
    },
    /// Prepare router-only dataset (tool_calls or NO_TOOL)
    PrepareRouter {
        #[arg(long)]
        tools: String,
        #[arg(long)]
        output: String,
        #[arg(long)]
        diagnose_prompt: String,
        #[arg(long)]
        chat_prompt: String,
        #[arg(long)]
        scenarios: Option<String>,
        #[arg(long, default_value = "24")]
        max_cases: usize,
        #[arg(long)]
        no_tool_coverage: bool,
        #[arg(long)]
        test_vectors: Option<String>,
    },
    /// Train the model using LoRA
    Train {
        #[arg(long)]
        model_path: String,
        #[arg(long)]
        train_data: String,
        #[arg(long)]
        output: String,
        #[arg(long, default_value = "1")]
        epochs: usize,
        #[arg(long, default_value = "1e-5")]
        lr: f64,
        #[arg(long, default_value = "16")]
        lora_r: usize,
        #[arg(long, default_value = "1")]
        batch_size: usize,
        #[arg(long, default_value = "4")]
        grad_accum: usize,
    },
    /// Evaluate a trained model or adapter
    Eval {
        #[arg(long)]
        model_path: String,
        #[arg(long)]
        test_data: String,
        #[arg(long, default_value = "16")]
        lora_r: usize,
        #[arg(long)]
        adapters: Option<String>,
    },
    /// Merge LoRA adapters into the base model
    Merge {
        #[arg(long)]
        model_path: String,
        #[arg(long)]
        adapters: String,
        #[arg(long)]
        output: String,
        #[arg(long, default_value = "16")]
        lora_r: usize,
    },
}

fn custom_load(varmap: &VarMap, path: &std::path::Path) -> Result<()> {
    let st = unsafe { candle_core::safetensors::MmapedSafetensors::new(path)? };
    let st_names: std::collections::HashSet<String> = st.tensors().iter().map(|(n, _)| n.clone()).collect();

    // Debug: print some model keys
    println!("Safetensors sample keys: {:?}", st_names.iter().take(5).collect::<Vec<_>>());

    let data = varmap.data().lock().unwrap();
    let mut updated = 0;
    for (name, var) in data.iter() {
        if st_names.contains(name) {
            let st_tensor = st.load(name, &var.device())?;
            var.set(&st_tensor)?;
            updated += 1;
        }
    }
    println!("Loaded {}/{} variables from {:?}", updated, data.len(), path);
    Ok(())
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Prepare { tools, output, scenarios, max_cases, system_prompt } => {
            println!("Preparing dataset...");
            let generator = DataGenerator::new(
                &PathBuf::from(tools),
                system_prompt.as_ref().map(PathBuf::from).as_deref()
            )?;

            let mut items = generator.generate_from_schema(max_cases)?;
            if let Some(s_path) = scenarios {
                let s_items = generator.generate_from_scenarios(&PathBuf::from(s_path))?;
                items.extend(s_items);
            }

            let mut out_text = String::new();
            for item in items {
                out_text.push_str(&serde_json::to_string(&item)?);
                out_text.push('\n');
            }
            fs::write(output, out_text)?;
            println!("Dataset prepared successfully.");
        }
        Commands::PrepareRouter {
            tools,
            output,
            diagnose_prompt,
            chat_prompt,
            scenarios,
            max_cases,
            no_tool_coverage,
            test_vectors,
        } => {
            println!("Preparing router dataset...");
            let cfg = RouterDatasetConfig {
                output: PathBuf::from(&output),
                tools_path: PathBuf::from(&tools),
                diagnose_prompt: PathBuf::from(&diagnose_prompt),
                chat_prompt: PathBuf::from(&chat_prompt),
                scenarios_path: scenarios.map(PathBuf::from),
                include_tool_coverage: !no_tool_coverage,
                max_cases,
            };

            let items = build_router_dataset(&cfg)?;
            write_jsonl(&cfg.output, &items)?;
            println!("Wrote {} examples to {}", items.len(), cfg.output.display());

            if let Some(test_vectors_path) = test_vectors {
                let vectors = build_tool_test_vectors(&cfg.tools_path, cfg.max_cases)?;
                write_test_vectors(&PathBuf::from(&test_vectors_path), &vectors)?;
                println!(
                    "Wrote {} tool test vectors to {}",
                    vectors.len(),
                    test_vectors_path
                );
            }
        }
        Commands::Train { model_path, train_data, output, epochs, lr, lora_r, batch_size, grad_accum } => {
            let device = Device::new_cuda(0).unwrap_or(Device::Cpu);
            println!("Training on device: {:?}", device);

            let model_dir = PathBuf::from(&model_path);
            let config_raw = fs::read_to_string(model_dir.join("config.json"))?;
            let config: Config = serde_json::from_str(&config_raw)?;

            let model_file = model_dir.join("model.safetensors");
            let mut tie_embeddings = true;
            if model_file.exists() {
                let st = unsafe { candle_core::safetensors::MmapedSafetensors::new(&model_file)? };
                tie_embeddings = !st.tensors().iter().any(|(name, _)| name == "lm_head.weight");
            }

            let varmap = VarMap::new();
            let vb = VarBuilder::from_varmap(&varmap, DType::BF16, &device);
            let model = Model::new(&config, lora_r, vb, tie_embeddings)?;

            if model_file.exists() {
                println!("Loading base weights...");
                custom_load(&varmap, &model_file)?;
            }

            let dataset = Dataset::load(&PathBuf::from(train_data))?;
            let tokenizer = Tokenizer::from_file(model_dir.join("tokenizer.json")).map_err(anyhow::Error::msg)?;

            let t_cfg = TrainerConfig { lr, epochs, batch_size, grad_accum, lora_r };
            let mut trainer = Trainer::new(model, &config, t_cfg, device, varmap);

            trainer.train(&dataset, &tokenizer)?;
            trainer.save_adapters(&PathBuf::from(output))?;
        }
        Commands::Eval { model_path, test_data, lora_r, adapters } => {
            let device = Device::new_cuda(0).unwrap_or(Device::Cpu);
            let model_dir = PathBuf::from(&model_path);
            let config_raw = fs::read_to_string(model_dir.join("config.json"))?;
            let config: Config = serde_json::from_str(&config_raw)?;

            let mut varmap = VarMap::new();
            let vb = VarBuilder::from_varmap(&varmap, DType::BF16, &device);
            let model = Model::new(&config, lora_r, vb, true)?;

            custom_load(&varmap, &model_dir.join("model.safetensors"))?;
            if let Some(a_path) = adapters {
                custom_load(&varmap, &PathBuf::from(a_path))?;
            }

            let dataset = Dataset::load(&PathBuf::from(test_data))?;
            let tokenizer = Tokenizer::from_file(model_dir.join("tokenizer.json")).map_err(anyhow::Error::msg)?;

            let mut correct = 0;
            for i in 0..dataset.len() {
                let item = &dataset.items[i];
                // For eval, we want to prompt with all messages EXCEPT the last model response
                let mut eval_item = item.clone();
                if let Some(last) = eval_item.messages.last_mut() {
                    if last.role == "assistant" || last.role == "model" {
                       eval_item.messages.pop();
                    }
                }

                let prompt = eval_item.to_prompt() + "<assistant>\n";
                let encoding = tokenizer.encode(prompt, true).map_err(anyhow::Error::msg)?;
                let input_tensor = Tensor::new(encoding.get_ids(), &device)?.unsqueeze(0)?;

                println!("\nTest Case {}:", i + 1);
                let user_text = item.messages.get(0).and_then(|m| m.content.as_deref()).unwrap_or("");
                println!("User: {}", user_text);

                let output_ids = model.generate(&input_tensor, 64, &device)?;
                let output_text = tokenizer.decode(&output_ids, true).map_err(anyhow::Error::msg)?;

                println!("Model Output: {}", output_text);
                let expected_text = item.messages.last().and_then(|m| m.content.as_deref()).unwrap_or("");
                println!("Expected: {}", expected_text);

                if output_text.contains(expected_text) || expected_text.contains(&output_text) {
                    correct += 1;
                }
            }
            println!("\nEvaluation complete: {}/{} correct", correct, dataset.len());
        }
        Commands::Merge { model_path, adapters, output, lora_r } => {
            let device = Device::Cpu; // Use CPU for merging to avoid OOM
            let model_dir = PathBuf::from(&model_path);
            let config_raw = fs::read_to_string(model_dir.join("config.json"))?;
            let config: Config = serde_json::from_str(&config_raw)?;

            println!("Loading model for merging...");
            let varmap = VarMap::new();
            let vb = VarBuilder::from_varmap(&varmap, DType::BF16, &device);
            let mut model = Model::new(&config, lora_r, vb, true)?;

            custom_load(&varmap, &model_dir.join("model.safetensors"))?;
            custom_load(&varmap, &PathBuf::from(adapters))?;

            println!("Merging adapters...");
            model.merge_adapters()?;

            println!("Saving merged model to {}...", output);
            varmap.save(output)?;
            println!("Merged model saved successfully.");
        }
    }

    Ok(())
}
