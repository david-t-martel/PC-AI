# PC_AI Quick Context

> For rapid session restoration - read this first
> Updated: 2026-01-23 | Version: 3.0.0

## What Is This Project?

**PC_AI** is a local LLM-powered PC diagnostics framework with 8 PowerShell modules.

## Current State (Test Fixing Phase)

| Component | Status |
|-----------|--------|
| 8 Modules | All functional |
| Unified CLI | `PC-AI.ps1` |
| Pester Tests | ~79% pass rate (173/218) |
| GitHub Actions | CI/CD configured |
| Rust Tools | 8/10 installed |
| Ollama LLM | qwen2.5-coder:7b primary |

## Test Status (2026-01-23)

| Module | Tests | Passed | Failed | Skipped |
|--------|-------|--------|--------|---------|
| PC-AI.Network | 24 | 24 | 0 | 0 |
| PC-AI.USB | 24 | 24 | 0 | 0 |
| PC-AI.Hardware | 33 | 33 | 0 | 0 |
| PC-AI.LLM | 28 | 28 | 0 | 0 |
| PC-AI.Cleanup | 26 | 26 | 0 | 0 |
| PC-AI.Performance | 22 | 19 | 3 | 0 |
| PC-AI.Virtualization | TBD | TBD | TBD | TBD |

## Recent Work (2026-01-23) - Test Fixes

**Round 1**: test-automator + explore agents
- Fixed PC-AI.Network.Tests.ps1 (24/24)
- Fixed PC-AI.USB.Tests.ps1 (24/24)

**Round 2**: Parallel agents
- Fixed PC-AI.Hardware.Tests.ps1 (33/33)
- Fixed PC-AI.LLM.Tests.ps1 (28/28)
- Fixed PC-AI.Cleanup.Tests.ps1 (26/26)
- Fixed PC-AI.Performance.Tests.ps1 (19/22)

**Round 3**: Cross-cutting agents
- Admin-skip pattern implementation
- Encoding fix pattern (PS5.1/PS7+ compat)

## Key Code Patterns

```powershell
# Encoding (PS5.1/PS7+ compat)
[System.IO.File]::WriteAllText($path, $content, [System.Text.Encoding]::UTF8)

# Admin skip pattern
-Skip:(-not $script:IsAdmin)

# Module-scoped mock
Mock Get-CimInstance { ... } -ModuleName PC-AI.Hardware

# API mocking
Mock Invoke-RestMethod {
    param($Uri)
    if ($Uri -match "/api/tags") { Get-MockOllamaResponse -Type ModelList }
} -ModuleName PC-AI.LLM
```

## Quick Commands

```powershell
# Navigate to project
cd C:\Users\david\PC_AI

# Run all tests
.\Tests\.pester.ps1 -Type Unit

# Run specific test file
Invoke-Pester Tests/Unit/PC-AI.LLM.Tests.ps1 -Output Detailed

# Check LLM status
Import-Module .\Modules\PC-AI.LLM -Force
Get-LLMStatus -TestConnection
```

## Active Issues

1. `Optimize-Disks` context failures in PC-AI.Performance
2. `CursorPosition` console errors in `Watch-VSockPerformance`
3. TestDrive path concatenation in some tests
4. Admin tests skipped when not elevated (~19 tests)

## Next Steps

1. Fix remaining ~26 test failures
2. Push to GitHub as public repository
3. Test with LM Studio agents
4. Document API for LLM integration

## For Full Context

Read: `C:\Users\david\PC_AI\.claude\context\project-context.md`
Also: `C:\Users\david\PC_AI\.claude\context\pc-ai-project-context.md`
