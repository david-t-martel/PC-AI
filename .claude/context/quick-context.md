# PC_AI Quick Context

> For rapid session restoration - read this first
> Updated: 2026-01-28 | Version: 5.2.0

## What Is This Project?

**PC_AI** is a local LLM-powered PC diagnostics framework with:
- 10 PowerShell modules (NEW: PC-AI.Common)
- **Native Rust acceleration** (Consolidated pcai_core_lib + C# Hybrid)
- **LLM Integration** (Ollama, LM Studio, vLLM, FunctionGemma)

## Current State (Rust Consolidation Complete)

| Component | Status |
|-----------|--------|
| 10 PowerShell Modules | All functional |
| Unified CLI | `PC-AI.ps1` |
| **Git Status** | **Clean (all committed)** |
| **Latest Commit** | **06092bb** |
| Rust Structure | **Consolidated into pcai_core_lib** |
| Native FFI Tests | Updated for new structure |

## Security Status

| Alert | Status |
|-------|--------|
| Dependabot High Severity | ⚠️ Review required |
| CVE-2024-30105 | ✓ Fixed (System.Text.Json 8.0.5) |
| CVE-2024-43485 | ✓ Fixed (System.Text.Json 8.0.5) |

## Recent Session (2026-01-28)

**8 Commits Pushed (84 files):**
1. `c561a13` chore: update gitignore and rgignore patterns
2. `8d8a38c` refactor(rust): consolidate pcai crates into pcai_core_lib modules
3. `939dfcc` refactor(csharp): update native modules for Rust consolidation
4. `dc69c1b` feat(modules): add PC-AI.Common module and tool parameter validation
5. `989ba0e` feat(training): enhance FunctionGemma training with Docker and profiling
6. `0f619a7` feat(training): add Rust-based FunctionGemma trainer
7. `1200f97` test: update FFI tests and add new integration tests
8. `06092bb` chore: update context and configuration files

## Rust Workspace Changes

**Before (standalone crates):**
```
Native/pcai_core/
├── pcai_core_lib/
├── pcai_performance/  ← REMOVED
├── pcai_search/       ← REMOVED
└── pcai_system/       ← REMOVED
```

**After (consolidated):**
```
Native/pcai_core/
└── pcai_core_lib/src/
    ├── lib.rs
    ├── fs/           ← File ops
    ├── performance/  ← Disk, memory, process
    ├── search/       ← File/content search
    ├── system/       ← Logs, paths
    └── telemetry/    ← USB, hardware
```

## Key Files (Updated Paths)

| Category | Path |
|----------|------|
| Rust Workspace | `Native/pcai_core/Cargo.toml` |
| Core Library | `Native/pcai_core/pcai_core_lib/src/lib.rs` |
| Performance | `Native/pcai_core/pcai_core_lib/src/performance/mod.rs` |
| Search | `Native/pcai_core/pcai_core_lib/src/search/mod.rs` |
| System | `Native/pcai_core/pcai_core_lib/src/system/mod.rs` |
| C# Core | `Native/PcaiNative/PcaiCore.cs` |
| C# Performance | `Native/PcaiNative/PerformanceModule.cs` |

## New Projects Added

| Project | Description |
|---------|-------------|
| `Deploy/rust-functiongemma-train/` | Rust-based training data generator |
| `Modules/PC-AI.Common/` | Shared PowerShell utilities |
| `Deploy/functiongemma-finetune/Dockerfile` | Docker training support |

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

# Check Dependabot alert
gh browse /security/dependabot/1
```

## Next Steps

1. **Validate Build**: Run `cargo build --release` to verify consolidation
2. **Run Tests**: Execute FFI test suite
3. **Review Alert**: Check Dependabot high-severity vulnerability
4. **Test Docker**: Validate FunctionGemma Docker training workflow

## Recommended Agents

| Agent | Purpose |
|-------|---------|
| rust-pro | Validate consolidated workspace builds |
| test-runner | Execute FFI test suite |
| security-auditor | Review Dependabot high-severity alert |
| csharp-pro | Verify P/Invoke bindings |

## For Full Context

- **Latest Context**: `.claude/context/pcai-context-20260128.md`
- **Native Details**: `.claude/context/native-acceleration-context.md`
- **Full Project**: `.claude/context/project-context.md`
- **Context Index**: `.claude/context/context-index.json`
