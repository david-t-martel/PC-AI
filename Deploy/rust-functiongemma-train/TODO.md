# TODO - Rust FunctionGemma (PC_AI)

This TODO captures the minimum work required to reach feature parity with
Deploy/functiongemma-finetune (Python) and to enable a Rust-only router runtime.

## Build environment
- [x] Use CargoTools wrapper for all builds/tests (Tools/Invoke-RustBuild.ps1).
- [x] Keep lld-link optional; default to link.exe unless explicitly enabled.
- [x] Ensure LLVM lld-link path is configured (C:\Program Files\LLVM\bin\lld-link.exe).

## P0 - I/O parity (required for drop-in replacement)
- [x] Implement OpenAI-compatible Chat Completions server (POST /v1/chat/completions).
- [x] Accept tools schema (Config/pcai-tools.json) and return message.tool_calls.
- [x] Support router prompt format: [MODE], [SYSTEM_PROMPT], [USER_REQUEST].
- [x] Emit NO_TOOL when no tool is needed (chat mode or non-tool cases).
- [x] Provide a tool-call parser that matches FunctionGemma expectations.

## P0 - Dataset + prompt parity
- [x] Router dataset generator (prepare_dataset.py parity) implemented via `prepare-router`:
  - Modes: diagnose/chat
  - System prompts: DIAGNOSE.md + CHAT.md
  - Scenario file: Deploy/functiongemma-finetune/scenarios.json
  - Tool coverage from pcai-tools.json
- [x] Ensure chat template rendering uses the tokenizer template with tools.
- [x] Add prompt masking so user/developer content does not contribute to loss.
- [x] Emit tool test vectors alongside tool-coverage datasets (parity with generate_training_data.py). Implemented via `prepare-router --test-vectors`.

## P0 - Training parity
- [ ] LoRA/QLoRA support with target modules (q/k/v/o/gate/up/down). (LoRA done; QLoRA stub wired, quantization pending)
- [x] Warmup + LR scheduling (linear or cosine).
- [x] Resume from checkpoint.
- [ ] Eval split and optional early stopping. (early stopping wired; eval split pending)
- [x] Save PEFT-style adapter outputs + tokenizer metadata.

## P0 - Runtime inference parity
- [ ] Load base model + LoRA adapters, or merged model.
- [ ] Match FunctionGemma chat template behavior.
- [ ] Provide deterministic generation settings for routing (low temp, short max tokens).
- [ ] Expose model + tools + version in /v1/models or /health endpoints.

## P1 - Tests and regressions
- [ ] Port Python unit tests for dataset and schema handling.
- [ ] Add router eval harness against a local runtime.
- [x] Validate tool call accuracy on scenarios.json and test vectors.

## P1 - PC_AI integration
- [x] PowerShell wrapper to replace Python tool_router.py.
- [x] Update Tools/run-functiongemma-tests.ps1 to prefer Rust pipeline.
- [x] Add config in Config/llm-config.json to point router base URL to Rust runtime.

## P2 - Performance + UX
- [ ] Incremental dataset generation and streaming JSONL output.
- [ ] Memory/throughput metrics in runtime server.
- [ ] Optional GPU selection and memory limits in config.
- [x] Pre-tokenize datasets and cache token IDs on disk (memmap2) for faster training/eval.
- [x] Add prompt packing (multiple short samples per batch) to improve GPU utilization.
- [x] Add deterministic eval metrics (tool-name accuracy + argument exact match) with JSON output.
- [x] Add JSON schema validation for tool call outputs (reject invalid arguments early).

## Crate candidates (easy wins)
- hf-hub: download and cache gated models.
- tokenizers: fast HF tokenizer and chat template support.
- safetensors: safe model weights IO.
- minijinja: render chat templates (Jinja-compatible).
- axum: lightweight HTTP server for OpenAI-compatible endpoints.
- tracing + tracing-subscriber: structured logs + log filtering.
- tower-http: runtime middleware (trace, timeouts, compression).
- schemars: generate JSON schema from Rust tool definitions.
- jsonschema: validate tool schemas and dataset payloads.

## Structure proposal
- [x] Convert to a Rust workspace:
  - [x] rust-functiongemma-runtime (server) - Deploy/rust-functiongemma-runtime
  - [x] rust-functiongemma-train (dataset + training) - Deploy/rust-functiongemma-train
  - [ ] rust-functiongemma-core (shared model/prompt/util)
