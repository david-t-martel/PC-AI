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
  1. FunctionGemma (vLLM) selects tools from `Config/pcai-tools.json`
  2. Tool outputs are gathered
  3. Primary LLM (Ollama/vLLM/LM Studio) writes the response

## Prompt contracts
- Diagnose mode: `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md`
  - Output must be valid JSON per `Config/DIAGNOSE_TEMPLATE.json`
  - Evidence-first: tie findings to exact report/log lines
- Chat mode: `CHAT.md` (concise, safe, actionable)

## LLM + Router integration
- Provider config: `Config/llm-config.json`
  - `ollama` → `hvsock://ollama` → 127.0.0.1:11434
  - `vllm` → `hvsock://vllm` → 127.0.0.1:8000
  - `lmstudio` → `hvsock://lmstudio` → 127.0.0.1:1234
- HVSocket aliases: `Config/hvsock-proxy.conf`
- Router entry points: `Invoke-FunctionGemmaReAct`, `Invoke-LLMChatRouted`

## WSL / Docker / LLM stack debugging
Use these when diagnosing LLM stack failures or virtualization issues:
- WSL status: `wsl --status`, `wsl -l -v`
- WSL health: `Get-WSLEnvironmentHealth`, `Invoke-WSLNetworkToolkit -Mode diagnose`
- Docker health: `docker version`, `docker info`, `Get-DockerStatus`
- GPU in containers: `docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi`
- LLM endpoints:
  - Ollama: `GET http://localhost:11434/api/tags`
  - vLLM (OpenAI compat): `GET http://127.0.0.1:8000/v1/models`
  - LM Studio: `GET http://127.0.0.1:1234/v1/models`

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
- Align `DIAGNOSE.md` tool calls (SearchDocs/GetSystemInfo/SearchLogs) with `Config/pcai-tools.json`.
- Reconcile diagnose-mode JSON-only requirement with `llm-config.json` response settings (markdown/reasoning).
- Confirm router base URL vs HVSocket routing (vLLM reachable via `hvsock://vllm` or update config).
- Replace external script references (e.g., `C:\\Scripts\\...`) with module cmdlets or add them to repo.
- Expand tool coverage for hardware/disk/USB/network to match `DIAGNOSE_LOGIC.md` expectations.
