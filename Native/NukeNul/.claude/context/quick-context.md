# NukeNul Quick Context

## What It Does
Deletes Windows reserved filenames (nul, con, prn, aux, com1-9, lpt1-9) that cannot be removed normally.

## Architecture
- **Rust DLL** (`nuker_core.dll`): Parallel file walker + Win32 DeleteFileW API
- **C# CLI** (`NukeNul.exe`): JSON output, .NET 8, framework-dependent

## Status: DEPLOYED
- Build: Working
- Tests: Passing (100% deletion success)
- Deployed: `C:\Users\david\bin\`
- Performance: 17.5M files scanned in ~4.5 minutes

## Installation Location
```
C:\Users\david\bin\
  NukeNul.exe              # C# CLI (151 KB)
  NukeNul.dll              # .NET assembly (26 KB)
  NukeNul.deps.json        # Dependency manifest
  NukeNul.runtimeconfig.json  # Runtime config
  nuker_core.dll           # Rust DLL (1.2 MB)
```

## Source Code Location
```
C:\Users\david\PC_AI\Native\NukeNul\
  Program.cs           # C# CLI (243 lines)
  NukeNul.csproj       # .NET 8 project
  build.ps1            # Build script
  test.ps1             # Test script
  delete-nul-files.ps1 # PowerShell wrapper (canonical)
  nuker_core\
    src\lib.rs         # Rust core (327 lines)
    Cargo.toml         # Rust config
  bin\Release\net8.0\win-x64\
    NukeNul.exe        # Built CLI
    nuker_core.dll     # Built DLL
```

## Script Symlinks (consolidated)
All point to canonical: `C:\Users\david\PC_AI\Native\NukeNul\delete-nul-files.ps1`
- `C:\Users\david\delete-nul-files.ps1` → symlink
- `C:\codedev\socat\delete-nul-files.ps1` → symlink
- `C:\codedev\stm32-merge\delete-nul-files.ps1` → symlink

## Build & Test
```powershell
cd C:\Users\david\PC_AI\Native\NukeNul
.\build.ps1            # Full build (Rust + C#)
.\test.ps1             # Run integration tests
```

## Usage
```powershell
# Direct execution
C:\Users\david\bin\NukeNul.exe C:\path\to\scan

# Via wrapper script (auto-detects NukeNul.exe, fallback to PowerShell)
C:\Users\david\PC_AI\Native\NukeNul\delete-nul-files.ps1 -SearchPath C:\path
```

## JSON Output Format
```json
{
  "tool": "Nuke-Nul",
  "target": "C:\\",
  "timestamp": "2026-01-23T10:37:38Z",
  "status": "Success",
  "performance": {
    "mode": "Rust/Parallel",
    "threads": 22,
    "elapsed_ms": 239744
  },
  "results": {
    "scanned": 14553658,
    "deleted": 1,
    "errors": 0
  }
}
```

## Key Technical Details
1. C# files are in ROOT directory (not a subdirectory)
2. RuntimeIdentifier is win-x64 (output goes to net8.0\win-x64\)
3. Uses `\\?\` extended-length paths for reserved filename deletion
4. JSON output for LLM/automation consumption
5. Framework-dependent build (requires .NET 8 runtime)

## Key Rust Dependencies
- `ignore` (ripgrep's parallel walker)
- `windows-sys` (Win32 API)
- `widestring` (UTF-16 conversion)

## Verified Scan Results (2026-01-23)
| Drive | Files Scanned | Deleted | Time |
|-------|--------------|---------|------|
| T:\ | 2,912,509 | 0 | 10.4s |
| C:\ | 14,553,658 | 1 | 4m 0s |

