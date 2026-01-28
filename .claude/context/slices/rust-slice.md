# Rust Context Slice - PC_AI

**Updated**: 2026-01-28 (Session 3)
**For Agents**: rust-pro, architect-reviewer

## Completed This Session

- ✅ All clippy errors fixed (commit c32d6cb)
- ✅ Training data generation working (27 examples)
- ✅ TOOLS.md generated and validated (12/12 tools)

## Active Rust Projects

### 1. rust-functiongemma-train
**Path**: `Deploy/rust-functiongemma-train/`
**Status**: Dataset generation complete, training loop needs LoRA
**Build**: `.\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-train build`

**Modules**:
- `src/trainer.rs` - Training loop (needs LoRA support)
- `src/dataset.rs` - Dataset loading
- `src/eval.rs` - Evaluation metrics
- `src/model.rs` - Model abstraction
- `src/schema_utils.rs` - Tool schema parsing

**P0 TODO**:
- LoRA/QLoRA with target modules (q/k/v/o/gate/up/down)
- Warmup + LR scheduling
- Checkpoint resume
- Save PEFT-style adapter outputs

### 2. rust-functiongemma-runtime
**Path**: `Deploy/rust-functiongemma-runtime/`
**Status**: Heuristic engine working, model inference experimental
**Build**: `.\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-runtime build`

**Endpoints**:
- `GET /health`
- `GET /v1/models`
- `POST /v1/chat/completions` (heuristic only)

**P0 TODO**:
- Full OpenAI-compatible Chat Completions
- Router prompt format: `[MODE], [SYSTEM_PROMPT], [USER_REQUEST]`
- Load base model + LoRA adapters

### 3. pcai_core_lib (Native Acceleration)
**Path**: `Native/pcai_core/pcai_core_lib/`
**Status**: Complete, tested
**Modules**: fs, performance, search, system, telemetry

## Crate Dependencies (Recommended)
```toml
hf-hub = "0.4"        # HF model downloads
tokenizers = "0.21"   # Fast tokenization
safetensors = "0.5"   # Model weights IO
minijinja = "2.5"     # Chat templates
axum = "0.8"          # HTTP server
tracing = "0.1"       # Logging
```

## Build Environment
- Use CargoTools wrapper: `Tools/Invoke-RustBuild.ps1`
- Default linker: link.exe (lld-link optional)
- Cache root: `T:\RustCache\` or `$LOCALAPPDATA\RustCache\`

## Key Files
- `Deploy/rust-functiongemma-train/TODO.md` - Full task list
- `Deploy/rust-functiongemma-runtime/README.md` - Runtime docs
- `.claude/plans/rust-llm-tooling-enhancement.md` - LLM tooling plan
