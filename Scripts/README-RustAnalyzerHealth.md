# Rust-Analyzer Health Monitoring

## Quick Reference

### Check Current Status
```powershell
.\Scripts\Test-RustAnalyzerHealth.ps1
```

### Kill Multiple Instances
```powershell
.\Scripts\Test-RustAnalyzerHealth.ps1 -Force
```

### Detailed Process Inspection
```powershell
.\Scripts\Test-RustAnalyzerHealth.ps1 -Detailed
```

### Custom Memory Threshold
```powershell
.\Scripts\Test-RustAnalyzerHealth.ps1 -WarnThresholdMB 1000
```

## Expected Healthy State

```
Status: HEALTHY
Processes: 1 main + 1 proc-macro-srv
Total Memory: ≤ 1500 MB
Lock File: Present at T:\RustCache\rust-analyzer\ra.lock
Issues Found: (none)
```

## Common Issues & Quick Fixes

### Multiple Instances Running
```powershell
# Kill extras
.\Scripts\Test-RustAnalyzerHealth.ps1 -Force

# Verify PATH
Get-Command rust-analyzer | Select-Object Source
# Should be: C:\Users\david\.local\bin\rust-analyzer-wrapper.*
```

### High Memory Usage
```powershell
# Check if wrapper is active (lock file should exist)
Test-Path T:\RustCache\rust-analyzer\ra.lock

# If missing, restart to use wrapper
Get-Process rust-analyzer | Stop-Process -Force
# VS Code will auto-restart via wrapper
```

### Stale Lock File
```powershell
# Verify no processes
Get-Process rust-analyzer* -ErrorAction SilentlyContinue

# Remove if confirmed stale
Remove-Item T:\RustCache\rust-analyzer\ra.lock -Force
```

### Wrapper Not Used
```powershell
# Check PATH resolution
Get-Command rust-analyzer

# Fix PATH (temporary)
$env:PATH = "C:\Users\david\.local\bin;$env:PATH"

# Fix PATH (permanent)
# Control Panel → System → Environment Variables
# Move C:\Users\david\.local\bin to top of User PATH
# Restart VS Code
```

## Health Check Components

### 1. Process Detection
- Identifies main rust-analyzer processes
- Filters out proc-macro-srv (expected child)
- Reports memory usage per process
- Detects singleton violations

### 2. Lock File Validation
- Checks `T:\RustCache\rust-analyzer\ra.lock` existence
- Detects stale locks (>5 min with no process)
- Validates lock file timing vs process start time

### 3. Configuration Audit
- Wrapper script presence
- PATH resolution priority
- Environment variables (RA_LRU_CAPACITY, CHALK_SOLVER_MAX_SIZE, RA_PROC_MACRO_WORKERS)
- VS Code settings alignment

### 4. Enforcement
- Force kill option for runaway processes
- Automatic issue detection
- Actionable recommendations

## Expected Environment Variables

When wrapper is active, rust-analyzer should have:
```
RA_LRU_CAPACITY=64
CHALK_SOLVER_MAX_SIZE=10
RA_PROC_MACRO_WORKERS=1
```

Check with:
```powershell
# View process environment (requires admin)
$proc = Get-Process rust-analyzer
(Get-CimInstance Win32_Process -Filter "ProcessId = $($proc.Id)").CommandLine
```

## Integration with PC_AI

The health check script can be integrated into PC_AI diagnostics:
- Add to `Get-PcDiagnostics.ps1` for comprehensive system reports
- Schedule periodic runs via Task Scheduler
- Alert on memory threshold breaches
- Auto-remediate stale locks

## Files

- **Health Check Script**: `C:\Users\david\PC_AI\Scripts\Test-RustAnalyzerHealth.ps1`
- **Wrapper Script**: `C:\Users\david\.local\bin\rust-analyzer-wrapper.ps1`
- **Lock File**: `T:\RustCache\rust-analyzer\ra.lock`
- **Mutex Name**: `Local\rust-analyzer-singleton`

## Architecture

```
VS Code → rust-analyzer command → PATH resolution
                                 ↓
                     C:\Users\david\.local\bin\rust-analyzer-wrapper.cmd
                                 ↓
                     Check mutex Local\rust-analyzer-singleton
                                 ↓
                     Create lock T:\RustCache\rust-analyzer\ra.lock
                                 ↓
                     Set env: RA_LRU_CAPACITY=64, etc.
                                 ↓
                     Spawn: T:\RustCache\rustup\...\rust-analyzer.exe
                                 ↓
                     Monitor: Single instance, memory limited
```

## Troubleshooting Decision Tree

```
Is rust-analyzer running?
├─ No → Normal, no action needed
└─ Yes
   ├─ How many main instances?
   │  ├─ 1 → Good, check memory
   │  └─ >1 → BAD: Run with -Force to kill extras
   │
   ├─ Memory usage?
   │  ├─ < 1.5GB → Good
   │  └─ > 1.5GB → Check if wrapper is active (lock file exists)
   │     ├─ Lock file present → Wrapper active but high usage anyway
   │     │                      → Check workspace size, proc-macros
   │     └─ Lock file absent → Wrapper NOT used
   │                           → Check PATH resolution
   │                           → Restart rust-analyzer
   │
   └─ Lock file stale?
      ├─ No → Normal
      └─ Yes (file exists, no process) → Remove manually
```

## Related Documentation

- **Plan**: `.claude/plans/rust-analyzer-consolidation-plan.md`
- **VS Code Config**: `.vscode/settings.json`
- **PC_AI Docs**: `CLAUDE.md`
