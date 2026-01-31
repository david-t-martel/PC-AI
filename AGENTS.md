# AGENTS.md

Local-first diagnostics agent guidance for PC_AI (PowerShell + Rust/C# + local LLMs).

## High-level goals
- Deterministic diagnostics with explicit tool execution (no hallucinated system state).
- Safety-first: read-only by default; destructive actions require explicit consent.
- Local LLM reasoning with clear prompts and structured output.
- Performance via Rust native DLLs and Rust CLI fallbacks.

## Architecture quick map
- `PC-AI.ps1` is the unified CLI entry point.
- PowerShell modules live under `Modules/` (Hardware/Virtualization/USB/Network/Performance/Cleanup/LLM/Acceleration).
- Native acceleration: `Native/` (Rust DLLs → C# P/Invoke → PowerShell wrapper).
- Router pipeline (optional):
  1. FunctionGemma runtime selects tools from `Config/pcai-tools.json`
  2. Tool outputs are gathered
  3. Primary LLM (pcai-inference) writes the response

## Prompt contracts
- Diagnose mode: `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md`
  - Output must be valid JSON per `Config/DIAGNOSE_TEMPLATE.json`
  - Evidence-first: tie findings to exact report/log lines
- Chat mode: `CHAT.md` (concise, safe, actionable)

## LLM + Router integration
- Provider config: `Config/llm-config.json`
  - `pcai-inference` → `http://127.0.0.1:8080` (OpenAI-compatible)
  - `functiongemma` → `http://127.0.0.1:8000` (router runtime)
- HVSocket aliases: `Config/hvsock-proxy.conf` (optional)
- Router entry points: `Invoke-FunctionGemmaReAct`, `Invoke-LLMChatRouted`

## LLM runtime debugging (native-first)
Use these when diagnosing LLM stack failures or routing issues:
- `Invoke-PcaiDoctor` (summary + recommendations)
- `Get-PcaiServiceHealth` (HTTP + FFI health checks)
- `Get-PcaiNativeStatus` / `Get-PcaiCapabilities` (native DLL availability)
- LLM endpoints:
  - pcai-inference: `GET http://127.0.0.1:8080/health` or `/v1/models`
  - FunctionGemma router: `GET http://127.0.0.1:8000/health` or `/v1/models`

## Tooling update workflow
1. Add/update tool in `Config/pcai-tools.json` (with `pcai_mapping`).
2. Add/update scenarios in `Deploy/functiongemma-finetune/scenarios.json`.
3. Rebuild training data + fine-tune FunctionGemma.
4. If tool changes impact diagnostics, update `DIAGNOSE.md` / `DIAGNOSE_LOGIC.md`.

## Native acceleration guidelines (CSharp_RustDLL)
- Prioritize heavy loops, deep recursion, or regex-heavy operations.
- Emit compact, stable JSON for LLM ingestion.
- Use C ABI (`extern "C"`) + C# P/Invoke wrapper for PowerShell.

## Known gaps / TODOs
- Define a versioned C ABI contract for Rust DLL exports (error codes, ownership).
- Standardize JSON schemas for native outputs (schema folder + version pinning).
- Provide progress + streaming updates for long native operations.
- Finalize eval split + QLoRA quantization for rust-functiongemma-train.

## Documentation automation
- Full pipeline: `Tools/Invoke-DocPipeline.ps1 -Mode Full`
- Docs-only: `Tools/Invoke-DocPipeline.ps1 -Mode DocsOnly`
- Lightweight summaries: `Tools/generate-auto-docs.ps1 -BuildDocs`
