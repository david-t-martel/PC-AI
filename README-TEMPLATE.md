# PC_AI - Local LLM-Powered PC Diagnostics Agent

![PowerShell Tests](https://github.com/yourusername/PC_AI/actions/workflows/powershell-tests.yml/badge.svg)
![Security Scan](https://github.com/yourusername/PC_AI/actions/workflows/security.yml/badge.svg)
![Release](https://github.com/yourusername/PC_AI/actions/workflows/release.yml/badge.svg)

> **Note:** Replace `yourusername` in the badge URLs with your actual GitHub username after pushing to GitHub.

## Overview

PC_AI is a local LLM-powered diagnostics and optimization agent for Windows 10/11 with WSL2 integration. It diagnoses hardware issues, analyzes system logs, and proposes optimizations for maximum system performance.

## Features

- **Hardware Diagnostics** - Device Manager errors, SMART status, system health
- **Virtualization Optimization** - WSL2, Hyper-V, Docker performance tuning
- **USB Diagnostics** - Controller status, device errors, stability analysis
- **Network Analysis** - Adapter configuration, connectivity issues
- **Performance Tuning** - Disk optimization, memory management, startup
- **Cleanup Utilities** - Duplicate files, PATH entries, system artifacts
- **LLM Integration** - Ollama-powered analysis and recommendations

## Quick Start

### Installation

```powershell
# Clone the repository
git clone https://github.com/yourusername/PC_AI.git
cd PC_AI

# Setup development environment
.\Setup-DevEnvironment.ps1

# Run comprehensive diagnostics (requires Administrator)
.\Get-PcDiagnostics.ps1
```

### Module Usage

```powershell
# Import a module
Import-Module .\Modules\PC-AI.Hardware\PC-AI.Hardware.psd1

# Run hardware diagnostics
Get-HardwareDiagnostics

# Check WSL2 optimization
Import-Module .\Modules\PC-AI.Virtualization\PC-AI.Virtualization.psd1
Get-WSL2OptimizationStatus

# Analyze USB issues
Import-Module .\Modules\PC-AI.USB\PC-AI.USB.psd1
Get-USBDiagnostics
```

## Modules

| Module | Description |
|--------|-------------|
| **PC-AI.Hardware** | Hardware diagnostics, SMART status, device errors |
| **PC-AI.Virtualization** | WSL2, Hyper-V, Docker optimization |
| **PC-AI.USB** | USB controller and device diagnostics |
| **PC-AI.Network** | Network adapter analysis and configuration |
| **PC-AI.Performance** | Performance tuning and optimization |
| **PC-AI.Cleanup** | System cleanup and maintenance |
| **PC-AI.LLM** | Ollama integration for AI-powered analysis |

## Development

### Prerequisites

- Windows 10 1809+ or Windows 11
- PowerShell 5.1 or PowerShell 7.4+
- Administrator privileges for diagnostics

### Setup Development Environment

```powershell
# Install dependencies
.\Setup-DevEnvironment.ps1

# Run tests
.\Tests\.pester.ps1

# Run local CI checks
.\Test-CI-Locally.ps1
```

### Testing

```powershell
# Run all tests
.\Tests\.pester.ps1

# Run with coverage
.\Tests\.pester.ps1 -Coverage

# Run specific module tests
.\Tests\.pester.ps1 -TestName "PC-AI.Hardware"
```

### Code Quality

```powershell
# Run PSScriptAnalyzer
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1

# Auto-fix issues
Invoke-ScriptAnalyzer -Path . -Recurse -Fix
```

## CI/CD Pipeline

The project uses GitHub Actions for continuous integration and deployment:

- **Automated Testing** - Tests run on PowerShell 5.1 and 7.4
- **Code Quality** - PSScriptAnalyzer enforces coding standards
- **Security Scanning** - Weekly scans for vulnerabilities
- **Automated Releases** - Tag-based release creation
- **Daily Health Checks** - Dependency and link validation

See [CI-CD-GUIDE.md](CI-CD-GUIDE.md) for detailed documentation.

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Make changes and test: `.\Test-CI-Locally.ps1`
4. Commit changes: `git commit -m "feat: Add new feature"`
5. Push to branch: `git push origin feature/my-feature`
6. Create a Pull Request

All contributions must:
- Pass PSScriptAnalyzer checks
- Include Pester tests
- Pass all CI checks
- Follow coding standards

## Documentation

- [DIAGNOSE.md](DIAGNOSE.md) - LLM assistant behavior and workflow
- [DIAGNOSE_LOGIC.md](DIAGNOSE_LOGIC.md) - Diagnostic reasoning decision trees
- [CI-CD-GUIDE.md](CI-CD-GUIDE.md) - CI/CD pipeline documentation
- [CLAUDE.md](CLAUDE.md) - Development guidelines and architecture

## Safety Constraints

- **Read-only by default** - Diagnostics collect data without modifications
- **No destructive operations** - Warnings and confirmations for risky actions
- **Backup requirements** - Disk repair requires backup confirmation
- **Professional escalation** - Hardware failures require professional diagnosis

## License

[Your License Here]

## Support

For issues or questions:
1. Check documentation in the `docs/` directory
2. Review [CI-CD-GUIDE.md](CI-CD-GUIDE.md) for troubleshooting
3. Open an issue on GitHub
4. Run diagnostics: `.\Get-PcDiagnostics.ps1`

## Acknowledgments

Built with PowerShell and automated with GitHub Actions.
