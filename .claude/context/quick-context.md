# PC_AI Quick Context

> For rapid session restoration - read this first
> Updated: 2026-01-27 | Version: 5.0.0

## What Is This Project?

**PC_AI** is a local LLM-powered PC diagnostics framework with:
- 8 PowerShell modules
- **Native Rust acceleration** (Rust DLL + C# Hybrid Framework)
- **LLM Integration** (Ollama, LM Studio, vLLM)

## Current State (Native Acceleration Phase 4 Complete)

| Component | Status |
|-----------|--------|
| 8 PowerShell Modules | All functional |
| Unified CLI | `PC-AI.ps1` |
| Pester Tests | ~81% pass rate (195/240) |
| **Native FFI Tests** | **90 passing** |
| **Rust Unit Tests** | **81 passing** |
| Ollama LLM | qwen2.5-coder:7b primary |
| Uncommitted Changes | **182 files** |

## Native Acceleration Status

| Phase | Module | Status | FFI Tests | Unit Tests |
|-------|--------|--------|-----------|------------|
| 1 | pcai_core_lib | COMPLETE | 16 | 26 |
| 2 | pcai_search | COMPLETE | 21 | 14 |
| 3 | pcai_performance | COMPLETE | 25 | 19 |
| 4 | pcai_system | COMPLETE | 28 | 22 |
| 5 | Integration | PLANNED | - | - |

**Latest Commit**: c338e11 "feat(native): add Phase 4 System Module with PATH analysis and log search"

## Architecture Pattern

```
Rust DLL (#[no_mangle] extern "C")
    |
    v
C# P/Invoke ([DllImport])
    |
    v
PowerShell Cmdlets (with fallback)
```

## Key Native Files

| Category | Path |
|----------|------|
| Rust Workspace | `Native/pcai_core/Cargo.toml` |
| Core Library | `Native/pcai_core/pcai_core_lib/src/lib.rs` |
| Search Module | `Native/pcai_core/pcai_search/src/*.rs` |
| System Module | `Native/pcai_core/pcai_core_lib/src/system.rs` |
| C# Wrappers | `Native/PcaiNative/*.cs` |
| System Wrapper | `Native/PcaiNative/SystemModule.cs` |
| FFI Tests | `Tests/Integration/FFI.*.Tests.ps1` |
| Built DLLs | `bin/*.dll` |

## Key LLM Files

| Category | Path |
|----------|------|
| LLM Module | `Modules/PC-AI.LLM/PC-AI.LLM.psm1` |
| Config | `Config/llm-config.json` |
| FunctionGemma | `Deploy/functiongemma-finetune/` |
| vLLM Docker | `Deploy/docker/vllm/` |

## Quick Commands

```powershell
# Navigate to project
cd C:\Users\david\PC_AI

# Build Rust (release)
cd Native\pcai_core && cargo build --release

# Build C#
cd Native\PcaiNative && dotnet build -c Release

# Run FFI tests
Invoke-Pester -Path 'Tests\Integration\FFI.*.Tests.ps1'

# Test native library availability
Add-Type -Path bin\PcaiNative.dll
[PcaiNative.PcaiCore]::GetDiagnostics() | ConvertTo-Json
```

## Code Patterns

```rust
// Rust FFI export
#[no_mangle]
pub extern "C" fn pcai_xxx(path: *const c_char) -> PcaiStringBuffer { ... }
```

```csharp
// C# P/Invoke
[DllImport("pcai_xxx.dll", CallingConvention = CallingConvention.Cdecl)]
internal static extern PcaiStringBuffer pcai_xxx(
    [MarshalAs(UnmanagedType.LPUTF8Str)] string path);

// Always free string buffers
var buffer = NativeXxx.pcai_xxx(path);
try { return buffer.ToManagedString(); }
finally { NativeCore.pcai_free_string_buffer(ref buffer); }
```

```powershell
# Pester test with Skip condition
BeforeDiscovery { $script:Available = ... }
It "Test" -Skip:(-not $script:Available) { ... }
```

## Next Steps (Phase 5 - Integration)

1. PowerShell cmdlet integration for native modules
2. Add `-UseNative` switch with graceful fallback
3. Performance benchmarks (native vs managed)
4. FunctionGemma vLLM tool router integration
5. Commit 182 pending changes

## Recommended Agents

| Agent | Purpose |
|-------|---------|
| test-runner | Run comprehensive FFI/Pester tests |
| deployment-engineer | CI/CD automation setup |
| code-reviewer | Review Phase 4 implementation |
| rust-pro | Rust module refinement |
| csharp-pro | C# wrapper improvements |

## For Full Context

- **Native Details**: `C:\Users\david\PC_AI\.claude\context\native-acceleration-context.md`
- **Full Project**: `C:\Users\david\PC_AI\.claude\context\project-context.md`
- **Framework Pattern**: `~/.claude/context/rust-csharp-hybrid-framework.md`
