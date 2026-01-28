# Rust FunctionGemma Workspace

This workspace groups the Rust runtime and training crates for FunctionGemma.
It is intentionally modular so the same base model can be retrained for
multiple tool sets or future router tasks.

## Members
- rust-functiongemma-runtime (Deploy/rust-functiongemma-runtime)
- rust-functiongemma-train (Deploy/rust-functiongemma-train)

## Build (CargoTools)
From repo root:

  .\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-runtime build
  .\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-train test

## Future
A shared core crate will be added for:
- Prompt formatting
- Tool schema parsing
- Chat template rendering
- Shared config and utilities
