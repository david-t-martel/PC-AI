use std::{env, net::SocketAddr};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let addr: SocketAddr = env::var("PCAI_ROUTER_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:8000".to_string())
        .parse()?;
    rust_functiongemma_runtime::serve(addr).await
}
