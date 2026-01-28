<#
.SYNOPSIS
    Health check and monitoring for singleton rust-analyzer operation.

.DESCRIPTION
    Monitors rust-analyzer processes, memory usage, lock file state, and enforces
    singleton operation. Detects multiple instances and can terminate runaway processes.

.PARAMETER Force
    Kill all rust-analyzer processes if multiple instances detected.

.PARAMETER Detailed
    Show detailed process information including command-line arguments.

.PARAMETER WarnThresholdMB
    Memory threshold in MB to warn about high usage (default: 1500).

.EXAMPLE
    .\Test-RustAnalyzerHealth.ps1
    Perform basic health check.

.EXAMPLE
    .\Test-RustAnalyzerHealth.ps1 -Force
    Kill multiple rust-analyzer instances if detected.

.EXAMPLE
    .\Test-RustAnalyzerHealth.ps1 -Detailed -WarnThresholdMB 1000
    Show detailed process info and warn if memory exceeds 1GB.

.NOTES
    Part of rust-analyzer consolidation plan for PC_AI diagnostics.
    Lock file: T:\RustCache\rust-analyzer\ra.lock
    Wrapper mutex: Local\rust-analyzer-singleton
    Expected environment: RA_LRU_CAPACITY=64, CHALK_SOLVER_MAX_SIZE=10, RA_PROC_MACRO_WORKERS=1
#>

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Detailed,
    [int]$WarnThresholdMB = 1500
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Constants
$LOCK_FILE = "T:\RustCache\rust-analyzer\ra.lock"
$MUTEX_NAME = "Local\rust-analyzer-singleton"
$EXPECTED_WRAPPER = "C:\Users\david\.local\bin\rust-analyzer-wrapper.ps1"
$MAX_MEMORY_MB = 1500

# Color output helpers
function Write-Success { param($Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Warning { param($Message) Write-Host "[WARN] $Message" -ForegroundColor Yellow }
function Write-Error { param($Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Info { param($Message) Write-Host "[INFO] $Message" -ForegroundColor Cyan }

# Health check result object
$HealthCheck = [PSCustomObject]@{
    Timestamp = Get-Date
    ProcessCount = 0
    Processes = @()
    TotalMemoryMB = 0
    LockFileExists = $false
    LockFileStale = $false
    MultipleInstances = $false
    MemoryWarning = $false
    Issues = @()
    Recommendations = @()
}

Write-Info "=== Rust-Analyzer Health Check ==="
Write-Info "Timestamp: $($HealthCheck.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))"
Write-Host ""

# 1. Check for running rust-analyzer processes
Write-Info "Checking for rust-analyzer processes..."
$Processes = Get-Process -Name "rust-analyzer*" -ErrorAction SilentlyContinue

if ($null -eq $Processes) {
    Write-Success "No rust-analyzer processes running"
    $HealthCheck.ProcessCount = 0
} else {
    # Handle single process vs array
    if ($Processes -is [array]) {
        $HealthCheck.ProcessCount = $Processes.Count
    } else {
        $HealthCheck.ProcessCount = 1
        $Processes = @($Processes)
    }

    # Filter out proc-macro-srv (expected child process)
    $MainProcesses = $Processes | Where-Object { $_.ProcessName -notlike "*proc-macro-srv*" }
    $ProcMacroProcesses = $Processes | Where-Object { $_.ProcessName -like "*proc-macro-srv*" }
    $MainProcessCount = if ($MainProcesses) {
        if ($MainProcesses -is [array]) { $MainProcesses.Count } else { 1 }
    } else { 0 }

    $HealthCheck.Processes = $Processes | ForEach-Object {
        $memoryMB = [math]::Round($_.WorkingSet64 / 1MB, 2)
        $HealthCheck.TotalMemoryMB += $memoryMB

        [PSCustomObject]@{
            PID = $_.Id
            ProcessName = $_.ProcessName
            MemoryMB = $memoryMB
            StartTime = $_.StartTime
            Path = $_.Path
            CommandLine = if ($Detailed) {
                (Get-CimInstance Win32_Process -Filter "ProcessId = $($_.Id)").CommandLine
            } else {
                $null
            }
        }
    }

    Write-Host ""
    Write-Host "Process Details:" -ForegroundColor White
    Write-Host "----------------"

    if ($MainProcesses) {
        Write-Host "Main rust-analyzer processes: $MainProcessCount" -ForegroundColor Cyan
        foreach ($proc in $HealthCheck.Processes | Where-Object { $_.ProcessName -notlike "*proc-macro-srv*" }) {
            Write-Host "  PID: $($proc.PID)" -ForegroundColor Cyan
            Write-Host "  Memory: $($proc.MemoryMB) MB" -ForegroundColor $(
                if ($proc.MemoryMB -gt $WarnThresholdMB) { 'Red' }
                elseif ($proc.MemoryMB -gt ($WarnThresholdMB * 0.8)) { 'Yellow' }
                else { 'Green' }
            )
            Write-Host "  Started: $($proc.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
            Write-Host "  Path: $($proc.Path)"
            if ($Detailed -and $proc.CommandLine) {
                Write-Host "  Command: $($proc.CommandLine)"
            }
            Write-Host ""
        }
    }

    if ($ProcMacroProcesses) {
        $procMacroCount = if ($ProcMacroProcesses -is [array]) { $ProcMacroProcesses.Count } else { 1 }
        Write-Host "Proc-macro server processes (expected): $procMacroCount" -ForegroundColor Gray
        if ($Detailed) {
            foreach ($proc in $HealthCheck.Processes | Where-Object { $_.ProcessName -like "*proc-macro-srv*" }) {
                Write-Host "  PID: $($proc.PID) | Memory: $($proc.MemoryMB) MB" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    Write-Host "Total Memory: $([math]::Round($HealthCheck.TotalMemoryMB, 2)) MB" -ForegroundColor $(
        if ($HealthCheck.TotalMemoryMB -gt $MAX_MEMORY_MB) { 'Red' } else { 'Green' }
    )
    Write-Host ""

    # Check for multiple main instances (excluding proc-macro-srv)
    if ($MainProcessCount -gt 1) {
        $HealthCheck.MultipleInstances = $true
        Write-Error "Multiple rust-analyzer main instances detected ($MainProcessCount)!"
        $HealthCheck.Issues += "Multiple main instances running (singleton violation)"
        $HealthCheck.Recommendations += "Kill extra instances with -Force flag"
    } elseif ($MainProcessCount -eq 1) {
        Write-Success "Single main instance running (singleton enforced)"
    }

    # Check memory threshold
    if ($HealthCheck.TotalMemoryMB -gt $WarnThresholdMB) {
        $HealthCheck.MemoryWarning = $true
        Write-Warning "Memory usage exceeds threshold ($WarnThresholdMB MB)"
        $HealthCheck.Issues += "High memory usage: $([math]::Round($HealthCheck.TotalMemoryMB, 2)) MB"
        $HealthCheck.Recommendations += "Check for large workspace or proc-macro issues"
    }
}

# 2. Check lock file state
Write-Info "Checking lock file state..."
if (Test-Path $LOCK_FILE) {
    $HealthCheck.LockFileExists = $true
    $lockInfo = Get-Item $LOCK_FILE
    $ageMinutes = [math]::Round(((Get-Date) - $lockInfo.LastWriteTime).TotalMinutes, 1)

    Write-Host "  Lock file exists: $LOCK_FILE" -ForegroundColor Yellow
    Write-Host "  Last modified: $($lockInfo.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')) ($ageMinutes min ago)"
    Write-Host "  Size: $($lockInfo.Length) bytes"

    # Read lock file content if small
    if ($lockInfo.Length -lt 1024) {
        try {
            $lockContent = Get-Content $LOCK_FILE -ErrorAction SilentlyContinue
            if ($lockContent) {
                Write-Host "  Content: $lockContent"
            }
        } catch {
            Write-Host "  Content: [Cannot read - file locked]" -ForegroundColor Gray
        }
    }

    # Check if lock file is stale (no process but lock exists)
    if ($HealthCheck.ProcessCount -eq 0 -and $ageMinutes -gt 5) {
        $HealthCheck.LockFileStale = $true
        Write-Warning "Lock file exists but no process running (stale lock)"
        $HealthCheck.Issues += "Stale lock file detected"
        $HealthCheck.Recommendations += "Remove stale lock file: Remove-Item '$LOCK_FILE' -Force"
    }

    # Check if process running but old lock file
    if ($HealthCheck.ProcessCount -gt 0) {
        $oldestProcess = ($HealthCheck.Processes | Sort-Object StartTime | Select-Object -First 1)
        $processAgeMinutes = [math]::Round(((Get-Date) - $oldestProcess.StartTime).TotalMinutes, 1)

        if ($processAgeMinutes -lt $ageMinutes) {
            Write-Warning "Lock file older than process (possible wrapper issue)"
            $HealthCheck.Issues += "Lock file timestamp mismatch"
        }
    }
} else {
    Write-Success "No lock file present"

    if ($HealthCheck.ProcessCount -gt 0) {
        Write-Warning "Process running but no lock file (wrapper may not be used)"
        $HealthCheck.Issues += "Missing lock file with active process"
        $HealthCheck.Recommendations += "Ensure rust-analyzer started via wrapper: $EXPECTED_WRAPPER"
    }
}

# 3. Check for wrapper configuration
Write-Info "Checking wrapper configuration..."
if (Test-Path $EXPECTED_WRAPPER) {
    Write-Success "Wrapper script exists: $EXPECTED_WRAPPER"

    # Check if wrapper is in PATH
    $whichRA = Get-Command "rust-analyzer" -ErrorAction SilentlyContinue
    if ($whichRA) {
        $resolvedPath = $whichRA.Source
        Write-Host "  'rust-analyzer' resolves to: $resolvedPath"

        if ($resolvedPath -notlike "*wrapper*") {
            Write-Warning "PATH may not prioritize wrapper (direct exe found)"
            $HealthCheck.Issues += "Wrapper not in PATH or not prioritized"
            $HealthCheck.Recommendations += "Ensure wrapper directory is first in PATH"
        }
    }
} else {
    Write-Error "Wrapper script not found: $EXPECTED_WRAPPER"
    $HealthCheck.Issues += "Missing wrapper script"
    $HealthCheck.Recommendations += "Reinstall rust-analyzer wrapper"
}

# 4. Check environment variables
Write-Info "Checking rust-analyzer environment variables..."
$expectedEnv = @{
    'RA_LRU_CAPACITY' = '64'
    'CHALK_SOLVER_MAX_SIZE' = '10'
    'RA_PROC_MACRO_WORKERS' = '1'
}

foreach ($var in $expectedEnv.GetEnumerator()) {
    $value = [Environment]::GetEnvironmentVariable($var.Key)
    if ($value -eq $var.Value) {
        Write-Success "$($var.Key) = $value"
    } elseif ($null -ne $value) {
        Write-Warning "$($var.Key) = $value (expected: $($var.Value))"
    } else {
        Write-Warning "$($var.Key) not set (expected: $($var.Value))"
    }
}

# 5. Check VS Code configuration (if in workspace)
Write-Info "Checking VS Code configuration..."
$vscodeSettings = ".vscode\settings.json"
if (Test-Path $vscodeSettings) {
    try {
        $settings = Get-Content $vscodeSettings -Raw | ConvertFrom-Json
        $raServerPath = $settings.'rust-analyzer.server.path'

        if ($raServerPath) {
            Write-Host "  VS Code rust-analyzer path: $raServerPath"
            if ($raServerPath -like "*wrapper*") {
                Write-Success "VS Code configured to use wrapper"
            } else {
                Write-Warning "VS Code not using wrapper path"
                $HealthCheck.Issues += "VS Code may spawn direct rust-analyzer"
                $HealthCheck.Recommendations += "Update .vscode/settings.json to use wrapper"
            }
        } else {
            Write-Warning "No rust-analyzer.server.path set in VS Code"
        }
    } catch {
        Write-Warning "Cannot parse VS Code settings: $_"
    }
} else {
    Write-Host "  No .vscode/settings.json in current directory" -ForegroundColor Gray
}

# 6. Force kill if requested
if ($Force -and $HealthCheck.MultipleInstances) {
    Write-Host ""
    Write-Warning "FORCE MODE: Killing rust-analyzer main processes..."

    # Only kill main rust-analyzer processes, not proc-macro-srv
    $toKill = $HealthCheck.Processes | Where-Object { $_.ProcessName -notlike "*proc-macro-srv*" }
    foreach ($proc in $toKill) {
        try {
            Stop-Process -Id $proc.PID -Force
            Write-Success "Killed PID $($proc.PID)"
        } catch {
            Write-Error "Failed to kill PID $($proc.PID): $_"
        }
    }

    # Clean up lock file if stale
    if (Test-Path $LOCK_FILE) {
        Start-Sleep -Seconds 2
        if ((Get-Process -Name "rust-analyzer*" -ErrorAction SilentlyContinue).Count -eq 0) {
            Remove-Item $LOCK_FILE -Force -ErrorAction SilentlyContinue
            Write-Success "Removed lock file"
        }
    }
}

# 7. Summary Report
Write-Host ""
Write-Host "=== Health Check Summary ===" -ForegroundColor White
Write-Host ""

$status = if ($HealthCheck.Issues.Count -eq 0) { "HEALTHY" } else { "ISSUES DETECTED" }
$color = if ($HealthCheck.Issues.Count -eq 0) { "Green" } else { "Red" }

Write-Host "Status: $status" -ForegroundColor $color
Write-Host "Processes: $($HealthCheck.ProcessCount)"
Write-Host "Total Memory: $([math]::Round($HealthCheck.TotalMemoryMB, 2)) MB"
Write-Host "Lock File: $(if ($HealthCheck.LockFileExists) { 'Present' } else { 'Absent' })"

if ($HealthCheck.Issues.Count -gt 0) {
    Write-Host ""
    Write-Host "Issues Found:" -ForegroundColor Red
    foreach ($issue in $HealthCheck.Issues) {
        Write-Host "  - $issue" -ForegroundColor Yellow
    }
}

if ($HealthCheck.Recommendations.Count -gt 0) {
    Write-Host ""
    Write-Host "Recommendations:" -ForegroundColor Cyan
    foreach ($rec in $HealthCheck.Recommendations) {
        Write-Host "  - $rec"
    }
}

Write-Host ""
Write-Host "=== End Health Check ===" -ForegroundColor White

# Return health check object for programmatic use
return $HealthCheck
