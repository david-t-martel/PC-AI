# TODO - Rust FunctionGemma (PC_AI)

This TODO captures the minimum work required to reach feature parity with
Deploy/functiongemma-finetune (Python) and to enable a Rust-only router runtime.

## Build environment
- Use CargoTools wrapper for all builds/tests (Tools/Invoke-RustBuild.ps1).
- Keep lld-link optional; default to link.exe unless explicitly enabled.
- Ensure LLVM lld-link path is configured (C:\Program Files\LLVM\bin\lld-link.exe).

## P0 - I/O parity (required for drop-in replacement)
- Implement OpenAI-compatible Chat Completions server (POST /v1/chat/completions).
- Accept tools schema (Config/pcai-tools.json) and return message.tool_calls.
- Support router prompt format: [MODE], [SYSTEM_PROMPT], [USER_REQUEST].
- Emit NO_TOOL when no tool is needed (chat mode or non-tool cases).
- Provide a tool-call parser that matches FunctionGemma expectations.

## P0 - Dataset + prompt parity
- Router dataset generator (prepare_dataset.py parity) implemented via `prepare-router`:
  - Modes: diagnose/chat
  - System prompts: DIAGNOSE.md + CHAT.md
  - Scenario file: Deploy/functiongemma-finetune/scenarios.json
  - Tool coverage from pcai-tools.json
- Ensure chat template rendering uses the tokenizer template with tools.
- Add prompt masking so user/developer content does not contribute to loss.
- Emit tool test vectors alongside tool-coverage datasets (parity with generate_training_data.py). Implemented via `prepare-router --test-vectors`.

## P0 - Training parity
- LoRA/QLoRA support with target modules (q/k/v/o/gate/up/down).
- Warmup + LR scheduling (linear or cosine).
- Resume from checkpoint.
- Eval split and optional early stopping.
- Save PEFT-style adapter outputs + tokenizer metadata.

## P0 - Runtime inference parity
- Load base model + LoRA adapters, or merged model.
- Match FunctionGemma chat template behavior.
- Provide deterministic generation settings for routing (low temp, short max tokens).
- Expose model + tools + version in /v1/models or /health endpoints.

## P1 - Tests and regressions
- Port Python unit tests for dataset and schema handling.
- Add router eval harness against a local runtime.
- Validate tool call accuracy on scenarios.json and test vectors.

## P1 - PC_AI integration
- PowerShell wrapper to replace Python tool_router.py.
- Update Tools/run-functiongemma-tests.ps1 to prefer Rust pipeline.
- Add config in Config/llm-config.json to point router base URL to Rust runtime.

## P2 - Performance + UX
- Incremental dataset generation and streaming JSONL output.
- Memory/throughput metrics in runtime server.
- Optional GPU selection and memory limits in config.
- Pre-tokenize datasets and cache token IDs on disk (memmap2) for faster training/eval. (implemented)
- Add prompt packing (multiple short samples per batch) to improve GPU utilization. (implemented)
- Add deterministic eval metrics (tool-name accuracy + argument exact match) with JSON output. (implemented)
- Add JSON schema validation for tool call outputs (reject invalid arguments early). (implemented)

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
- Convert to a Rust workspace:
  - rust-functiongemma-runtime (server) - Deploy/rust-functiongemma-runtime
  - rust-functiongemma-train (dataset + training) - Deploy/rust-functiongemma-train
  - rust-functiongemma-core (shared model/prompt/util)
