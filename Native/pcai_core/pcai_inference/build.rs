use std::env;

fn main() {
    // Detect CUDA installation
    if env::var("CUDA_PATH").is_ok() || env::var("CUDA_HOME").is_ok() {
        println!("cargo:rustc-cfg=has_cuda");
        println!("cargo:rerun-if-env-changed=CUDA_PATH");
        println!("cargo:rerun-if-env-changed=CUDA_HOME");
    }

    // Rerun build script if feature flags change
    println!("cargo:rerun-if-changed=build.rs");
}
