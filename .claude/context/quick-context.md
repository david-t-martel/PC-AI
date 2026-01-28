# PC_AI Quick Context

> For rapid session restoration - read this first
> Updated: 2026-01-27 | Version: 5.1.0

## What Is This Project?

**PC_AI** is a local LLM-powered PC diagnostics framework with:
- 9 PowerShell modules (NEW: PC-AI.CLI)
- **Native Rust acceleration** (Rust DLL + C# Hybrid Framework)
- **LLM Integration** (Ollama, LM Studio, vLLM, FunctionGemma)

## Current State (Post-Refactoring Session)

| Component | Status |
|-----------|--------|
| 9 PowerShell Modules | All functional |
| Unified CLI | `PC-AI.ps1` |
| **Git Status** | **Clean (all committed)** |
| **Latest Commit** | **2bbbbbc** |
| Native FFI Tests | 90 passing |
| Rust Unit Tests | 81 passing |

## Security Status

| CVE | Package | Status |
|-----|---------|--------|
| CVE-2024-30105 | System.Text.Json | ✓ Fixed (8.0.5) |
| CVE-2024-43485 | System.Text.Json | ✓ Fixed (8.0.5) |
| CVE-2026-0994 | protobuf | ⚠️ No upstream fix |

## Recent Session (2026-01-27)

**13 Commits Pushed:**
1. `c13119b` refactor(native): split PcaiNative.cs into modular components
2. `51b027d` refactor(rust): modularize telemetry into submodules
3. `69a1fb3` feat(llm): add routed chat and log search capabilities
4. `bcca140` feat(usb): add native USB diagnostics support
5. `92b9303` feat(virtualization): enhance WSL/Docker health checks
6. `0df1b25` feat(modules): add CLI module and update manifests
7. `7759a4c` feat(deploy): enhance FunctionGemma training pipeline
8. `e772123` chore(config): update LLM and tool configurations
9. `4c99b34` docs: add agent guidance and architecture documentation
10. `fa1806c` test: add comprehensive test suite
11. `a5fabd5` chore: update reports and tooling scripts
12. `21f9911` refactor(cli): simplify PC-AI.ps1 entry point
13. `2bbbbbc` security: fix CVE-2025-4565 and modernize dependencies

## Dependency Updates Applied

| Ecosystem | Package | Old → New |
|-----------|---------|-----------|
| Rust | sysinfo | 0.32 → 0.38 |
| Rust | windows-sys | 0.59 → 0.61 |
| NuGet | Microsoft.PowerShell.SDK | 7.4.1 → 7.5.4 |
| pip | torch | 2.3.0 → 2.5.0 |
| pip | protobuf | 4.25.0 → 6.31.1 |

## Key Native Files (Refactored)

| Category | Path |
|----------|------|
| Rust Workspace | `Native/pcai_core/Cargo.toml` |
| Core Library | `Native/pcai_core/pcai_core_lib/src/lib.rs` |
| Telemetry Module | `Native/pcai_core/pcai_core_lib/src/telemetry/` (NEW structure) |
| VMM Health | `Native/pcai_core/pcai_core_lib/src/vmm_health.rs` (NEW) |
| C# Core | `Native/PcaiNative/PcaiCore.cs` (was PcaiNative.cs) |
| C# Diagnostics | `Native/PcaiNative/PcaiDiagnostics.cs` (NEW) |
| C# Safety | `Native/PcaiNative/SafetyInterlock.cs` (NEW) |

## Quick Commands

```powershell
# Navigate to project
cd C:\Users\david\PC_AI

# Build Rust (release)
cd Native\pcai_core && cargo build --release

# Build C#
cd Native\PcaiNative && dotnet build -c Release

# Run all tests
Invoke-Pester -Path Tests/

# Check for vulnerabilities
dotnet list package --vulnerable
```

## Next Steps

1. **Test Suite**: Run full Pester tests to verify refactoring
2. **Monitor CVE**: Watch protobuf for CVE-2026-0994 fix
3. **FunctionGemma**: Test training with updated torch/transformers
4. **Documentation**: Update Native/PcaiNative structure docs

## Recommended Agents

| Agent | Purpose |
|-------|---------|
| test-runner | Verify tests pass post-refactoring |
| python-pro | Test FunctionGemma training pipeline |
| security-auditor | Monitor protobuf CVE status |

## For Full Context

- **Latest Context**: `.claude/context/pcai-context-20260127.md`
- **Native Details**: `.claude/context/native-acceleration-context.md`
- **Full Project**: `.claude/context/project-context.md`
- **Context Index**: `.claude/context/context-index.json`
