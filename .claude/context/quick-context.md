# PC_AI Quick Context

> For rapid session restoration - read this first
> Updated: 2025-01-23 | Version: 2.0.0

## What Is This Project?

**PC_AI** is a local LLM-powered PC diagnostics framework with 8 PowerShell modules.

## Current State (All Working)

| Component | Status |
|-----------|--------|
| 8 Modules | All functional |
| Unified CLI | `PC-AI.ps1` |
| Pester Tests | 85% coverage target |
| GitHub Actions | CI/CD configured |
| Rust Tools | 8/10 installed |
| Ollama LLM | qwen2.5-coder:7b primary |

## Modules

1. **PC-AI.Hardware** - Device errors, disk health, USB, network
2. **PC-AI.Virtualization** - WSL2, Hyper-V, Docker
3. **PC-AI.USB** - USB/WSL passthrough
4. **PC-AI.Network** - Network diagnostics, VSock
5. **PC-AI.Performance** - Disk space, process monitoring
6. **PC-AI.Cleanup** - PATH cleanup, temp files, duplicates
7. **PC-AI.LLM** - Ollama integration, LLM analysis
8. **PC-AI.Acceleration** - Rust tools, parallel processing (NEW)

## Recent Work (2025-01-23)

- PC-AI.Acceleration module completed
- 8 Rust tools integrated: rg, fd, procs, bat, hyperfine, tokei, eza, sd
- 2 missing tools: dust, btm (not installed)
- 4 bugs fixed (switch syntax, fd args, parallel pattern, Include param)
- Performance: ripgrep 44.6x faster than Select-String

## Key Design Decisions

1. **Fallback pattern**: Rust tool -> PS7+ parallel -> sequential PS
2. **PS7+ parallelism**: `ForEach-Object -Parallel` (not .NET Parallel.ForEach)
3. **Function standards**: CmdletBinding, OutputType, ValidateSet
4. **Module structure**: Public/ for exports, Private/ for helpers

## Quick Commands

```powershell
# Navigate to project
cd C:\Users\david\PC_AI

# Check status
.\PC-AI.ps1 status

# Run diagnostics
.\PC-AI.ps1 diagnose all

# Check Rust tools
Import-Module .\Modules\PC-AI.Acceleration
Get-RustToolStatus | Format-Table Tool, Available, Version

# Run tests
.\Tests\.pester.ps1
```

## Missing Rust Tools (Install)

```powershell
# Disk usage analyzer
winget install sharkdp.dust

# System monitor
winget install bottom
```

## Key Files

| File | Purpose |
|------|---------|
| `PC-AI.ps1` | Unified CLI |
| `Modules/PC-AI.Acceleration/` | Rust tool wrappers |
| `Tests/PesterConfiguration.psd1` | Test config (85% coverage) |
| `.github/workflows/` | CI/CD pipelines |

## Next Steps

1. Install dust and btm
2. Add acceleration tests
3. Integrate acceleration into other modules

## For Full Context

Read: `C:\Users\david\PC_AI\.claude\context\project-context.md`
