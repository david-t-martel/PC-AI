# PC-AI: Local LLM-Powered PC Diagnostics Framework

A comprehensive PowerShell 7+ framework for Windows PC diagnostics, optimization, and system analysis powered by local LLMs via Ollama/LM Studio.

## Features

- **Hardware Diagnostics**: Device errors, SMART status, USB controllers, network adapters
- **Virtualization Support**: WSL2 optimization, Hyper-V status, Docker diagnostics
- **Performance Acceleration**: Rust tool integration (ripgrep, fd, procs) with PS7+ parallelism
- **LLM Analysis**: Local AI-powered diagnostic interpretation via Ollama
- **Unified CLI**: Single entry point for all diagnostic and optimization tasks

## Requirements

- **Windows 10/11** with PowerShell 7.0+
- **Optional**: Ollama or LM Studio for LLM features
- **Optional**: Rust CLI tools for acceleration (fd, ripgrep, procs, bat, etc.)

## Quick Start

```powershell
# Import the main modules
Import-Module .\Modules\PC-AI.Hardware\PC-AI.Hardware.psd1
Import-Module .\Modules\PC-AI.Acceleration\PC-AI.Acceleration.psd1

# Run hardware diagnostics (requires Admin)
.\Get-PcDiagnostics.ps1

# Check available Rust tools for acceleration
Get-RustToolStatus

# Fast file search using fd
Find-FilesFast -Path "C:\Projects" -Pattern "*.ps1"

# Fast content search using ripgrep
Search-ContentFast -Path "C:\Scripts" -Pattern "function" -FilePattern "*.ps1"
```

## Modules

| Module | Description |
|--------|-------------|
| **PC-AI.Hardware** | Device manager, disk health, USB, network diagnostics |
| **PC-AI.Virtualization** | WSL2, Hyper-V, Docker status and optimization |
| **PC-AI.USB** | USB device management and WSL passthrough |
| **PC-AI.Network** | Network diagnostics, VSock optimization |
| **PC-AI.Performance** | Disk optimization, resource monitoring |
| **PC-AI.Cleanup** | PATH cleanup, duplicate detection, temp cleanup |
| **PC-AI.LLM** | Ollama/LM Studio integration for AI analysis |
| **PC-AI.Acceleration** | Rust tools integration with PS7+ parallelism |

## Acceleration Module

The `PC-AI.Acceleration` module provides significant performance improvements by leveraging Rust CLI tools with automatic fallback to PowerShell:

### Supported Rust Tools

| Tool | Use Case | Speedup |
|------|----------|---------|
| `fd` | File finding | 5-10x |
| `ripgrep` (rg) | Content search | **40x+** |
| `procs` | Process listing | Better formatting |
| `bat` | File viewing | Syntax highlighting |
| `hyperfine` | Benchmarking | Statistical accuracy |

### Performance Pattern

All acceleration functions follow a consistent fallback:
1. **Rust tool** (fastest) - if available
2. **PS7+ parallel** - ForEach-Object -Parallel
3. **Sequential PS** - compatible fallback

### Example: Content Search Performance

```
Directory: C:\Users (1000+ files)
----------------------------------------
ripgrep (Rust):     391ms
Select-String (PS): 17,471ms
Speedup:            44.6x
```

## Unified CLI

```powershell
# Diagnostics
.\PC-AI.ps1 diagnose hardware
.\PC-AI.ps1 diagnose wsl
.\PC-AI.ps1 diagnose all

# Optimization
.\PC-AI.ps1 optimize wsl
.\PC-AI.ps1 optimize disk

# USB Management
.\PC-AI.ps1 usb list
.\PC-AI.ps1 usb attach <busid>

# LLM Analysis
.\PC-AI.ps1 analyze
.\PC-AI.ps1 analyze --model mistral

# Cleanup
.\PC-AI.ps1 cleanup path --dry-run
.\PC-AI.ps1 cleanup temp
```

## LLM Integration

PC-AI integrates with local LLM providers for intelligent diagnostic analysis:

### Ollama (Default)
```powershell
# Ensure Ollama is running
ollama serve

# Run analysis with default model (qwen2.5-coder:7b)
Invoke-PCDiagnosis -ReportPath ".\report.txt"
```

### LM Studio
```powershell
# Configure LM Studio endpoint
Set-LLMConfig -Provider lmstudio -BaseUrl "http://localhost:1234"

# Run analysis
Invoke-PCDiagnosis -ReportPath ".\report.txt"
```

### Recommended Models

| Model | Size | Best For |
|-------|------|----------|
| qwen2.5-coder:7b | 4GB | Technical analysis (default) |
| deepseek-r1:8b | 5GB | Complex reasoning |
| mistral:7b | 4GB | Fast general analysis |
| gemma3:12b | 7GB | High-quality responses |

## Testing

```powershell
# Run all tests with coverage
.\tests\.pester.ps1 -Type All -Coverage

# Run unit tests only
.\tests\.pester.ps1 -Type Unit

# Run integration tests
.\tests\.pester.ps1 -Type Integration
```

## Project Structure

```
PC_AI/
├── PC-AI.ps1                 # Unified CLI entry point
├── Get-PcDiagnostics.ps1     # Core diagnostics script
├── DIAGNOSE.md               # LLM system prompt
├── DIAGNOSE_LOGIC.md         # Decision tree for analysis
├── Modules/
│   ├── PC-AI.Hardware/       # Hardware diagnostics
│   ├── PC-AI.Virtualization/ # WSL2, Hyper-V, Docker
│   ├── PC-AI.USB/            # USB management
│   ├── PC-AI.Network/        # Network diagnostics
│   ├── PC-AI.Performance/    # Performance optimization
│   ├── PC-AI.Cleanup/        # System cleanup
│   ├── PC-AI.LLM/            # LLM integration
│   └── PC-AI.Acceleration/   # Rust tools + parallelism
├── Tests/                    # Pester test suites
├── Config/                   # Configuration files
└── Reports/                  # Generated diagnostic reports
```

## Safety

- **Read-only by default**: Diagnostics collect data without modifications
- **Explicit consent**: Destructive operations require confirmation
- **Backup warnings**: BIOS/disk operations include backup prompts
- **Dry-run support**: Preview changes before execution

## Contributing

1. Fork the repository
2. Create a feature branch
3. Run tests: `.\tests\.pester.ps1 -Type All`
4. Submit a pull request

## License

MIT License - See [LICENSE](LICENSE) for details.

## Acknowledgments

- [Rust CLI tools](https://github.com/sharkdp/fd) for performance acceleration
- [Ollama](https://ollama.ai/) for local LLM inference
- [Pester](https://pester.dev/) for PowerShell testing
