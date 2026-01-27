# TODO

## Now (stability + parity)
- [x] Replace external WSL/Docker script references in prompts with module cmdlets
- [x] Add module fallback when external WSL/Docker scripts are missing
- [ ] Add internal WSL network toolkit implementation for feature parity with the legacy script
- [x] Align tool schema with module cmdlets (SearchDocs/GetSystemInfo/SearchLogs vs pcai-tools.json)
- [x] Enforce JSON-only diagnose output in routed/diagnose flows
- [ ] Enforce JSON-only diagnose output in UI/TUI rendering paths

## Architecture alignments (C#/Rust backend as primary engine)
- [ ] Replace PowerShell-only diagnostics with Rust/C# native backends where feasible (logs, inventory, health checks)
- [ ] Define a versioned C ABI contract for all Rust DLL exports (error codes, result structs, memory ownership)
- [ ] Create a unified C# service layer that exposes Rust capabilities to PowerShell and TUI
- [ ] Standardize JSON schemas for native outputs (shared schema folder + version pinning)
- [ ] Add a capability registry (DLL presence, feature flags, CPU/GPU support) surfaced to PowerShell UI
- [ ] Centralize error translation (Rust error -> C# status -> PowerShell error record)
- [ ] Provide cancellation/timeouts across PowerShell -> C# -> Rust (Ctrl+C propagation)
- [ ] Add structured logging + metrics from native layer (ETW or JSON log file)

## Agentic interface robustness
- [ ] Ensure tool outputs are deterministic and bounded in size (truncate, summarize, or compress)
- [ ] Add retry/timeout policy per tool invocation (with per-tool max runtime)
- [ ] Add health gates for LLM providers (ollama/vllm/lmstudio) before tool routing
- [ ] Normalize tool result envelopes (Success/ExitCode/Warnings/Evidence)
- [ ] Expand diagnostic coverage to match DIAGNOSE_LOGIC.md expectations

## UI/TUI usability
- [ ] Add a unified status command (WSL/Docker/LLM/GPU/Native DLL status)
- [ ] Provide progress + streaming updates for long native operations
- [ ] Implement a one-command "doctor" flow for common failures (WSL/Docker/vLLM/Ollama)
- [ ] Add a concise summary view for JSON diagnose output (human-readable view)
- [ ] Document common workflows in README (diagnose, repair, analyze, optimize)

## WSL/Docker/vLLM/Ollama integration
- [ ] Ensure router base URL and hvsock mappings are consistent with actual services
- [ ] Add automatic detection of local endpoints (WSL vs host)
- [ ] Add container-aware GPU checks when Docker is present

## Testing + QA
- [ ] Add tests for module fallbacks when external scripts are missing
- [ ] Add tests for native DLL availability and graceful fallbacks
- [x] Add integration tests for router tool schema coverage and JSON output compliance
- [x] Add unit tests for routed JSON enforcement and TUI wrapper failures
- [ ] Add integration tests for router tool execution with mock tool outputs
