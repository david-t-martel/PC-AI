//! pcai-inference HTTP server

use pcai_inference::{
    backends::BackendType,
    config::{InferenceConfig, ServerConfig},
    http::run_server,
};
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Initialize tracing
    tracing_subscriber::registry()
        .with(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "pcai_inference=info,tower_http=debug".into()),
        )
        .with(tracing_subscriber::fmt::layer())
        .init();

    tracing::info!("Starting pcai-inference server");

    // Load configuration from file or use defaults
    let config = if let Ok(path) = std::env::var("PCAI_CONFIG") {
        tracing::info!("Loading configuration from {}", path);
        InferenceConfig::from_file(path)?
    } else {
        tracing::warn!("No PCAI_CONFIG environment variable, using placeholder config");
        return Err(anyhow::anyhow!(
            "Configuration required. Set PCAI_CONFIG environment variable to config file path"
        ));
    };

    // Create backend
    let backend_type = match &config.backend {
        #[cfg(feature = "llamacpp")]
        pcai_inference::config::BackendConfig::LlamaCpp { .. } => BackendType::LlamaCpp,

        #[cfg(feature = "mistralrs-backend")]
        pcai_inference::config::BackendConfig::MistralRs { .. } => BackendType::MistralRs,
    };

    let mut backend = backend_type.create()?;

    // Load model
    tracing::info!("Loading model from {:?}", config.model.path);
    backend
        .load_model(config.model.path.to_str().ok_or_else(|| {
            anyhow::anyhow!("Invalid model path")
        })?)
        .await?;

    // Start server
    let server_config = config.server.unwrap_or_default();
    run_server(server_config, backend).await?;

    Ok(())
}
