#[cfg(feature = "model")]
use anyhow::{Context, Result};
#[cfg(feature = "model")]
use hf_hub::{api::sync::Api, Repo, RepoType};
#[cfg(feature = "model")]
use minijinja::Environment;
#[cfg(feature = "model")]
use std::{fs, path::{Path, PathBuf}};
#[cfg(feature = "model")]
use tokenizers::Tokenizer;

#[cfg(feature = "model")]
#[allow(dead_code)]
pub struct ModelAssets {
    pub tokenizer: Tokenizer,
    pub chat_template: String,
}

#[cfg(feature = "model")]
#[allow(dead_code)]
impl ModelAssets {
    pub fn load(model_dir: &Path) -> Result<Self> {
        let tokenizer_path = model_dir.join("tokenizer.json");
        let template_path = model_dir.join("chat_template.jinja");
        let tokenizer = Tokenizer::from_file(&tokenizer_path)
            .map_err(anyhow::Error::msg)
            .with_context(|| format!("failed to load tokenizer: {}", tokenizer_path.display()))?;
        let chat_template = fs::read_to_string(&template_path)
            .with_context(|| format!("failed to read chat template: {}", template_path.display()))?;
        Ok(Self { tokenizer, chat_template })
    }

    pub fn render_chat(&self, context: &serde_json::Value) -> Result<String> {
        let mut env = Environment::new();
        env.add_template("chat", &self.chat_template)?;
        let tmpl = env.get_template("chat")?;
        Ok(tmpl.render(context)?)
    }
}

#[cfg(feature = "model")]
#[allow(dead_code)]
pub fn resolve_model_path(model_id: &str) -> Result<PathBuf> {
    let local = PathBuf::from(model_id);
    if local.exists() {
        return Ok(local);
    }

    let api = Api::new()?;
    let repo = Repo::with_revision(model_id.to_string(), RepoType::Model, "main".to_string());
    let api = api.repo(repo);

    let tokenizer_path = api.get("tokenizer.json")?;
    let template_path = api.get("chat_template.jinja")?;

    let root = tokenizer_path.parent().unwrap_or(Path::new("."));
    if !template_path.exists() {
        return Err(anyhow::anyhow!("chat_template.jinja not found after download"));
    }

    Ok(root.to_path_buf())
}

#[cfg(feature = "model")]
#[allow(dead_code)]
pub fn load_safetensors_summary(path: &Path) -> Result<usize> {
    let data = fs::read(path)?;
    let tensors = safetensors::SafeTensors::deserialize(&data)?;
    Ok(tensors.len())
}
