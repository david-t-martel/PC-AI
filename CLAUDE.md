# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**PC_AI** is a local LLM-powered PC diagnostics and optimization agent designed to:
- Diagnose hardware issues, device errors, and system problems
- Analyze event logs, SMART status, and device configurations
- Propose optimizations for disk, network, and system performance
- Clean up duplicates, PATH entries, and unnecessary system artifacts
- Route tool execution via FunctionGemma runtime before final LLM analysis

The agent operates on **Windows 10/11** with native-first inference via **pcai-inference**. WSL/Docker are optional and not required for the LLM stack.

## Architecture

```
PC_AI/
├── DIAGNOSE.md           # LLM system prompt defining assistant behavior
├── DIAGNOSE_LOGIC.md     # Branched reasoning decision tree for analysis
├── CHAT.md               # General chat system prompt
├── Get-PcDiagnostics.ps1 # Core hardware/device diagnostics script
├── Deploy/pcai-inference/        # Rust LLM inference engine (HTTP + FFI)
├── Deploy/rust-functiongemma-runtime/ # Rust router runtime
├── Deploy/rust-functiongemma-train/   # Rust router dataset + training
├── Deploy/functiongemma-finetune/ # Legacy Python training + router
└── CLAUDE.md             # This file
```

### Design Pattern

1. **DIAGNOSE.md** - Defines the LLM assistant's role, safety constraints, and workflow
2. **DIAGNOSE_LOGIC.md** - Branched reasoning logic for analyzing diagnostic output
3. **Get-PcDiagnostics.ps1** - Read-only PowerShell script that collects system data

The agent follows a **collect → parse → route → reason → recommend** workflow where diagnostics output is structured into categories, optional tool routing is executed via the FunctionGemma runtime, and the main LLM produces recommendations.

## Commands

### Run Hardware Diagnostics
```powershell
# Requires Administrator
.\Get-PcDiagnostics.ps1
# Creates: Desktop\Hardware-Diagnostics-Report.txt
```

### Output Sections
The diagnostic report contains:
1. **Device Manager Errors** - Devices with ConfigManagerErrorCode != 0
2. **Disk SMART Status** - Drive health via wmic
3. **System Event Errors** - Disk/USB errors from last 3 days
4. **USB Device Status** - USB controllers and device status
5. **Network Adapter Status** - Physical adapter configuration

## Scripts to Migrate from `~\*`

The following scripts from the home directory are candidates for consolidation into this project:

### Disk Optimization
- `Optimize-Disks.ps1` - Smart TRIM/defrag for SSD/HDD with scheduled task support

### Cleanup
- `clean_machine_path.ps1` - Remove duplicate/stale PATH entries
- `cleanup-duplicates.ps1` - Duplicate file detection and removal

### Performance
- `wezterm-performance-profiler.ps1` - Terminal startup/memory/render benchmarking

## Diagnostic Categories

### Priority Classification
- **Critical**: SMART failures, disk bad blocks, hardware virtualization disabled
- **High**: USB controller errors, device driver failures, service crashes
- **Medium**: Performance degradation, missing Defender exclusions, VMQ issues
- **Low**: Unused adapters, informational warnings

### ConfigManagerErrorCode Reference
| Code | Meaning |
|------|---------|
| 1 | Device not configured correctly |
| 10 | Device cannot start |
| 12 | Cannot find enough free resources |
| 22 | Device is disabled |
| 28 | Drivers not installed |
| 31 | Device not working properly |
| 43 | Device stopped responding |

## Safety Constraints

- **Read-only by default** - Diagnostics collect data without modifications
- **No destructive commands** without explicit user consent and backup warnings
- **Disk repair** (chkdsk /r) requires backup confirmation first
- **BIOS/firmware updates** need context and warning
- **Professional escalation** for suspected hardware failure

## Integration Points

### Event Log Queries
```powershell
# Disk/USB errors
Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2,3; StartTime=(Get-Date).AddDays(-3)}

```

### WMI/CIM Queries
```powershell
# Device errors
Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }

# Physical network adapters
Get-CimInstance Win32_NetworkAdapter | Where-Object { $_.PhysicalAdapter -eq $true }

# Disk status
wmic diskdrive get model, status
```

### FunctionGemma Router
- Tool schema: `Config/pcai-tools.json`
- Router interface: `Invoke-FunctionGemmaReAct` / `Invoke-LLMChatRouted`
- Training data: `Deploy/rust-functiongemma-train/` (legacy Python in `Deploy/functiongemma-finetune/`)
- Runtime: `Deploy/rust-functiongemma-runtime/`
- HVSocket aliases: `Config/hvsock-proxy.conf` with `hvsock://functiongemma` / `hvsock://pcai-inference`

## Expected Output Format

When reporting findings, use this structure:

```
## Summary
- [2-4 bullet points of key findings]

## Findings by Category
### Devices with Errors
### Disk Health
### USB Stability
### Network Adapters

## Priority Issues
- Critical: [list]
- High: [list]
- Medium: [list]

## Recommended Next Steps
1. [Numbered, safe actions]
2. [Warnings for risky operations]
```

## Development Notes

### Adding New Diagnostics
1. Add data collection to `Get-PcDiagnostics.ps1`
2. Add parsing logic to `DIAGNOSE_LOGIC.md`
3. Update category handling in `DIAGNOSE.md`

### Testing
```powershell
# Test diagnostics script runs without errors
.\Get-PcDiagnostics.ps1

# Verify report created
Test-Path "$env:USERPROFILE\Desktop\Hardware-Diagnostics-Report.txt"
```

### PowerShell Requirements
- Requires Administrator for full diagnostics
- Uses Get-CimInstance (not deprecated Get-WmiObject)
- Handles missing features gracefully with try/catch
