#Requires -Version 7.0
<#
.SYNOPSIS
    Unified test runner for PC_AI project

.DESCRIPTION
    Runs all test suites in the correct order:
    1. Rust unit tests (cargo test)
    2. C# wrapper tests (dotnet test)
    3. Pester integration tests (FFI tests)
    4. Module tests (PC-AI.* modules)

    IMPORTANT: Requires PowerShell 7+ for .NET 8 compatibility.

.PARAMETER Suite
    Which test suite(s) to run:
    - All: Run all tests (default)
    - Rust: Rust unit tests only
    - CSharp: C# wrapper tests only
    - Pester: Pester integration tests only
    - Module: PowerShell module tests only
    - Quick: Fast smoke test (Rust + core Pester)

.PARAMETER Verbose
    Show detailed test output

.PARAMETER FailFast
    Stop on first test failure

.EXAMPLE
    .\test-all.ps1
    Runs all test suites

.EXAMPLE
    .\test-all.ps1 -Suite Quick
    Runs fast smoke tests only

.EXAMPLE
    .\test-all.ps1 -Suite Pester -Verbose
    Runs Pester tests with detailed output
#>

[CmdletBinding()]
param(
    [ValidateSet('All', 'Rust', 'CSharp', 'Pester', 'Module', 'Quick')]
    [string]$Suite = 'All',

    [switch]$FailFast
)

$ErrorActionPreference = if ($FailFast) { 'Stop' } else { 'Continue' }

# Colors
$Colors = @{
    Success = 'Green'
    Error   = 'Red'
    Warning = 'Yellow'
    Info    = 'Cyan'
    Step    = 'Magenta'
    Dim     = 'DarkGray'
}

$RootDir = $PSScriptRoot
$NativeDir = Join-Path $RootDir 'Native'
$TestsDir = Join-Path $RootDir 'Tests'
$BinDir = Join-Path $RootDir 'bin'

# Results tracking
$Results = @{
    Rust    = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
    CSharp  = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
    Pester  = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
    Module  = @{ Passed = 0; Failed = 0; Skipped = 0; Duration = 0 }
}

function Write-TestStep {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor $Colors.Step
}

function Write-TestResult {
    param([string]$Message, [bool]$Success)
    $color = if ($Success) { $Colors.Success } else { $Colors.Error }
    $icon = if ($Success) { '[PASS]' } else { '[FAIL]' }
    Write-Host "  $icon $Message" -ForegroundColor $color
}

function Write-TestInfo {
    param([string]$Message)
    Write-Host "  [i] $Message" -ForegroundColor $Colors.Info
}

# ============================================================================
# Rust Tests
# ============================================================================

function Test-RustWorkspace {
    Write-TestStep "Running Rust unit tests"

    $rustWorkspace = Join-Path $NativeDir 'pcai_core'
    if (-not (Test-Path $rustWorkspace)) {
        Write-TestResult "Rust workspace not found: $rustWorkspace" -Success $false
        return
    }

    Push-Location $rustWorkspace
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        # Use cargo.exe directly to bypass any routing issues
        $cargoExe = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'
        if (-not (Test-Path $cargoExe)) {
            $cargoExe = 'cargo'
        }

        Write-Host "    Running: $cargoExe test --workspace" -ForegroundColor $Colors.Dim

        $output = & $cargoExe test --workspace 2>&1

        $sw.Stop()
        $Results.Rust.Duration = $sw.Elapsed.TotalSeconds

        # Parse test results - sum all crate results
        # Filter for actual summary lines (format: "test result: ok. N passed; N failed; N ignored...")
        # Exclude test names like "test result::tests::test_name"
        $summaryLines = $output | Where-Object { $_ -match 'test result: (ok|FAILED)\.' }
        foreach ($line in $summaryLines) {
            if ($line -match '(\d+) passed.*?(\d+) failed.*?(\d+) ignored') {
                $Results.Rust.Passed += [int]$Matches[1]
                $Results.Rust.Failed += [int]$Matches[2]
                $Results.Rust.Skipped += [int]$Matches[3]
            }
        }

        if ($LASTEXITCODE -eq 0) {
            Write-TestResult "Rust tests passed ($($Results.Rust.Passed) tests in $([math]::Round($sw.Elapsed.TotalSeconds, 2))s)" -Success $true
        }
        else {
            Write-TestResult "Rust tests failed" -Success $false
            if ($VerbosePreference -eq 'Continue') {
                $output | ForEach-Object { Write-Host "    $_" -ForegroundColor $Colors.Dim }
            }
            else {
                $output | Where-Object { $_ -match 'FAILED|error\[' } | ForEach-Object { Write-Host "    $_" -ForegroundColor $Colors.Error }
            }
        }
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# C# Tests
# ============================================================================

function Test-CSharpWrapper {
    Write-TestStep "Running C# wrapper tests"

    $csharpDir = Join-Path $NativeDir 'PcaiNative'
    if (-not (Test-Path $csharpDir)) {
        Write-TestResult "C# project not found: $csharpDir" -Success $false
        return
    }

    # Check for test project
    $testProject = Join-Path $TestsDir 'Native\csharp\PcaiNative.Tests\PcaiNative.Tests.csproj'
    if (-not (Test-Path $testProject)) {
        Write-TestInfo "C# test project not found, skipping"
        $Results.CSharp.Skipped = 1
        return
    }

    Push-Location (Split-Path $testProject)
    try {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        Write-Host "    Running: dotnet test" -ForegroundColor $Colors.Dim
        $output = & dotnet test --nologo --verbosity quiet 2>&1

        $sw.Stop()
        $Results.CSharp.Duration = $sw.Elapsed.TotalSeconds

        if ($LASTEXITCODE -eq 0) {
            # Parse results if available
            $resultLine = $output | Where-Object { $_ -match 'Passed.*Failed.*Skipped' }
            if ($resultLine) {
                Write-TestResult "C# tests: $resultLine" -Success $true
            }
            else {
                Write-TestResult "C# tests passed" -Success $true
            }
            $Results.CSharp.Passed = 1
        }
        else {
            Write-TestResult "C# tests failed" -Success $false
            $Results.CSharp.Failed = 1
        }
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# Pester Tests
# ============================================================================

function Test-PesterIntegration {
    Write-TestStep "Running Pester integration tests"

    $integrationDir = Join-Path $TestsDir 'Integration'
    if (-not (Test-Path $integrationDir)) {
        Write-TestResult "Integration tests directory not found: $integrationDir" -Success $false
        return
    }

    # Check for Pester
    $pester = Get-Module -Name Pester -ListAvailable | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $pester -or $pester.Version.Major -lt 5) {
        Write-TestInfo "Pester 5+ required. Install with: Install-Module Pester -Force"
        $Results.Pester.Skipped = 1
        return
    }

    Import-Module Pester -MinimumVersion 5.0 -Force

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    # Find all FFI test files
    $testFiles = Get-ChildItem -Path $integrationDir -Filter 'FFI.*.Tests.ps1'

    if ($testFiles.Count -eq 0) {
        Write-TestInfo "No FFI test files found"
        $Results.Pester.Skipped = 1
        return
    }

    foreach ($testFile in $testFiles) {
        Write-Host "    Running: $($testFile.Name)" -ForegroundColor $Colors.Dim

        try {
            $config = New-PesterConfiguration
            $config.Run.Path = $testFile.FullName
            $config.Run.PassThru = $true
            $config.Output.Verbosity = if ($VerbosePreference -eq 'Continue') { 'Detailed' } else { 'Minimal' }

            $result = Invoke-Pester -Configuration $config

            $Results.Pester.Passed += $result.PassedCount
            $Results.Pester.Failed += $result.FailedCount
            $Results.Pester.Skipped += $result.SkippedCount

            $success = $result.FailedCount -eq 0
            Write-TestResult "$($testFile.BaseName): $($result.PassedCount) passed, $($result.FailedCount) failed, $($result.SkippedCount) skipped" -Success $success
        }
        catch {
            Write-TestResult "$($testFile.BaseName): Error - $_" -Success $false
            $Results.Pester.Failed += 1
        }
    }

    $sw.Stop()
    $Results.Pester.Duration = $sw.Elapsed.TotalSeconds
}

# ============================================================================
# Module Tests
# ============================================================================

function Test-Modules {
    Write-TestStep "Running module tests"

    $moduleTests = Join-Path $TestsDir 'Unit'
    if (-not (Test-Path $moduleTests)) {
        Write-TestInfo "Module tests directory not found, skipping"
        $Results.Module.Skipped = 1
        return
    }

    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    $testFiles = Get-ChildItem -Path $moduleTests -Filter '*.Tests.ps1' -Recurse

    if ($testFiles.Count -eq 0) {
        Write-TestInfo "No module test files found"
        $Results.Module.Skipped = 1
        return
    }

    Import-Module Pester -MinimumVersion 5.0 -Force -ErrorAction SilentlyContinue

    foreach ($testFile in $testFiles) {
        Write-Host "    Running: $($testFile.Name)" -ForegroundColor $Colors.Dim

        try {
            $config = New-PesterConfiguration
            $config.Run.Path = $testFile.FullName
            $config.Run.PassThru = $true
            $config.Output.Verbosity = 'Minimal'

            $result = Invoke-Pester -Configuration $config

            $Results.Module.Passed += $result.PassedCount
            $Results.Module.Failed += $result.FailedCount
            $Results.Module.Skipped += $result.SkippedCount
        }
        catch {
            $Results.Module.Failed += 1
        }
    }

    $sw.Stop()
    $Results.Module.Duration = $sw.Elapsed.TotalSeconds

    Write-TestResult "Module tests: $($Results.Module.Passed) passed, $($Results.Module.Failed) failed" -Success ($Results.Module.Failed -eq 0)
}

# ============================================================================
# Quick Smoke Test
# ============================================================================

function Test-QuickSmoke {
    Write-TestStep "Running quick smoke test"

    # 1. Check DLLs exist
    Write-Host "    Checking DLLs..." -ForegroundColor $Colors.Dim
    $coreDll = Join-Path $BinDir 'pcai_core_lib.dll'
    $searchDll = Join-Path $BinDir 'pcai_search.dll'
    $wrapperDll = Join-Path $BinDir 'PcaiNative.dll'

    $dllsExist = (Test-Path $coreDll) -and (Test-Path $searchDll) -and (Test-Path $wrapperDll)

    if (-not $dllsExist) {
        Write-TestResult "DLLs not found in $BinDir. Run Native\build.ps1 first." -Success $false
        return
    }
    Write-TestResult "DLLs present" -Success $true

    # 2. Add bin directory to PATH for native DLL resolution
    $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Process')
    if ($currentPath -notlike "*$BinDir*") {
        [System.Environment]::SetEnvironmentVariable('PATH', "$BinDir;$currentPath", 'Process')
        Write-Host "    Added $BinDir to process PATH" -ForegroundColor $Colors.Dim
    }

    # 3. Load and test native module
    Write-Host "    Testing native module..." -ForegroundColor $Colors.Dim
    try {
        Add-Type -Path $wrapperDll -ErrorAction Stop

        $coreAvailable = [PcaiNative.PcaiCore]::IsAvailable
        $searchAvailable = [PcaiNative.PcaiSearch]::IsAvailable

        if ($coreAvailable -and $searchAvailable) {
            $coreVersion = [PcaiNative.PcaiCore]::Version
            $searchVersion = [PcaiNative.PcaiSearch]::Version
            Write-TestResult "Native modules loaded (Core: $coreVersion, Search: $searchVersion)" -Success $true
        }
        else {
            Write-TestResult "Native modules loaded but not functional" -Success $false
        }
    }
    catch {
        Write-TestResult "Failed to load native module: $_" -Success $false
    }

    # 4. Quick functional test
    Write-Host "    Testing duplicate detection..." -ForegroundColor $Colors.Dim
    try {
        $testPath = $env:TEMP
        $stats = [PcaiNative.PcaiSearch]::FindDuplicatesStats($testPath, 0, $null, $null)

        if ($stats.Status -eq [PcaiNative.PcaiStatus]::Success) {
            Write-TestResult "Duplicate detection working (scanned $($stats.FilesScanned) files in $($stats.ElapsedMs)ms)" -Success $true
        }
        else {
            Write-TestResult "Duplicate detection returned status: $($stats.Status)" -Success $false
        }
    }
    catch {
        Write-TestResult "Duplicate detection failed: $_" -Success $false
    }
}

# ============================================================================
# Main Execution
# ============================================================================

$startTime = Get-Date
Write-Host ""
Write-Host "PC_AI Test Runner" -ForegroundColor Cyan
Write-Host "==================" -ForegroundColor Cyan
Write-Host "Suite: $Suite"
Write-Host "Root: $RootDir"
Write-Host ""

switch ($Suite) {
    'All' {
        Test-RustWorkspace
        Test-CSharpWrapper
        Test-PesterIntegration
        Test-Modules
    }
    'Rust' {
        Test-RustWorkspace
    }
    'CSharp' {
        Test-CSharpWrapper
    }
    'Pester' {
        Test-PesterIntegration
    }
    'Module' {
        Test-Modules
    }
    'Quick' {
        Test-RustWorkspace
        Test-QuickSmoke
    }
}

# Summary
$endTime = Get-Date
$totalDuration = ($endTime - $startTime).TotalSeconds

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "TEST SUMMARY" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$totalPassed = 0
$totalFailed = 0
$totalSkipped = 0

foreach ($suite in $Results.Keys) {
    $r = $Results[$suite]
    $totalPassed += $r.Passed
    $totalFailed += $r.Failed
    $totalSkipped += $r.Skipped

    if ($r.Passed -gt 0 -or $r.Failed -gt 0 -or $r.Skipped -gt 0) {
        $status = if ($r.Failed -gt 0) { 'FAIL' } elseif ($r.Skipped -gt 0 -and $r.Passed -eq 0) { 'SKIP' } else { 'PASS' }
        $color = switch ($status) { 'PASS' { $Colors.Success } 'FAIL' { $Colors.Error } 'SKIP' { $Colors.Warning } }
        Write-Host ("  {0,-10} [{1}] {2} passed, {3} failed, {4} skipped ({5:F2}s)" -f $suite, $status, $r.Passed, $r.Failed, $r.Skipped, $r.Duration) -ForegroundColor $color
    }
}

Write-Host ""
$overallStatus = if ($totalFailed -gt 0) { 'FAILED' } else { 'PASSED' }
$overallColor = if ($totalFailed -gt 0) { $Colors.Error } else { $Colors.Success }
Write-Host "Overall: $overallStatus ($totalPassed passed, $totalFailed failed, $totalSkipped skipped)" -ForegroundColor $overallColor
Write-Host "Total time: $([math]::Round($totalDuration, 2)) seconds" -ForegroundColor $Colors.Dim
Write-Host ""

# Return exit code for CI
if ($totalFailed -gt 0) {
    exit 1
}
exit 0
