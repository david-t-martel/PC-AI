#Requires -Version 5.1
<#+
.SYNOPSIS
  Rust build helper that routes through CargoTools.

.DESCRIPTION
  Standardizes Rust builds with CargoTools env setup, sccache, and optional
  lld-link configuration. Intended for repeatable, LLM-friendly builds.

.PARAMETER Path
  Working directory to run cargo from.

.PARAMETER UseLld
  Enable lld-link (CARGO_USE_LLD=1). Default is disabled to avoid Windows link issues.

.PARAMETER NoLld
  Force link.exe (CARGO_USE_LLD=0).

.PARAMETER LlmDebug
  Enable CargoTools LLM debug defaults (RUST_BACKTRACE, verbose traces).

.PARAMETER RaPreflight
  Enable rust-analyzer diagnostics during CargoTools preflight.

.PARAMETER Preflight
  Enable CargoTools preflight checks (cargo check/clippy/fmt).

.PARAMETER PreflightMode
  Preflight mode: check|clippy|fmt|all.

.PARAMETER PreflightBlocking
  Fail build if preflight fails.

.EXAMPLE
  .\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-train test

.EXAMPLE
  .\Tools\Invoke-RustBuild.ps1 -Path Deploy\rust-functiongemma-train --use-lld build --release
#>
[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Path = (Get-Location).Path,
    [switch]$UseLld,
    [switch]$NoLld,
    [switch]$LlmDebug,
    [switch]$RaPreflight,
    [switch]$Preflight,
    [ValidateSet('check','clippy','fmt','all')]
    [string]$PreflightMode = 'check',
    [switch]$PreflightBlocking,
    [string[]]$CargoArgs,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Module -ListAvailable CargoTools)) {
    throw 'CargoTools module not found. Ensure it is installed under PSModulePath.'
}
if (-not (Get-Module CargoTools)) {
    Import-Module CargoTools -ErrorAction Stop
}

# Ensure LLVM lld-link path is configured for optional use
$llvmBin = 'C:\Program Files\LLVM\bin'
$lldPath = Join-Path $llvmBin 'lld-link.exe'
if (Test-Path $lldPath) {
    if (-not $env:CARGO_LLD_PATH) { $env:CARGO_LLD_PATH = $lldPath }
    if ($env:PATH -notlike "*${llvmBin}*") {
        $env:PATH = "$llvmBin;$env:PATH"
    }
}

# Configure CUDA environment for candle-core/cudarc builds
$cudaHelper = Join-Path $PSScriptRoot 'Initialize-CudaEnvironment.ps1'
if (Test-Path $cudaHelper) {
    . $cudaHelper
    $cudaInfo = Initialize-CudaEnvironment -Quiet
    if ($cudaInfo.Found) {
        Write-Verbose "CUDA environment configured: $($cudaInfo.CudaPath)"
    }
} else {
    Write-Verbose "CUDA helper not found at $cudaHelper"
}

# Normalize CMake environment for crates that use cmake/cc build scripts
$cmakeHelper = Join-Path $PSScriptRoot 'Initialize-CmakeEnvironment.ps1'
if (Test-Path $cmakeHelper) {
    . $cmakeHelper
    $cmakeInfo = Initialize-CmakeEnvironment -Quiet
    if ($cmakeInfo.Found -and $cmakeInfo.CmakeRoot) {
        Write-Verbose "CMake environment configured: $($cmakeInfo.CmakeRoot)"
    }
} else {
    Write-Verbose "CMake helper not found at $cmakeHelper"
}

# Default: do not use lld unless explicitly requested
# Default to link.exe unless explicitly enabled
$env:CARGO_USE_LLD = '0'
if ($UseLld) { $env:CARGO_USE_LLD = '1' }
if ($NoLld) { $env:CARGO_USE_LLD = '0' }

if ($Preflight) {
    $env:CARGO_PREFLIGHT = '1'
    $env:CARGO_PREFLIGHT_MODE = $PreflightMode
} else {
    $env:CARGO_PREFLIGHT = '0'
}

# rust-analyzer diagnostics are opt-in to avoid singleton contention by default
if ($RaPreflight) {
    $env:CARGO_RA_PREFLIGHT = '1'
} elseif (-not $env:CARGO_RA_PREFLIGHT) {
    $env:CARGO_RA_PREFLIGHT = '0'
}

if ($PreflightBlocking) {
    $env:CARGO_PREFLIGHT_BLOCKING = '1'
}

$wrapperArgs = @()
if ($LlmDebug) { $wrapperArgs += '--llm-debug' }
if ($UseLld) { $wrapperArgs += '--use-lld' }
if ($NoLld) { $wrapperArgs += '--no-lld' }

$finalArgs = if ($CargoArgs -and $CargoArgs.Count -gt 0) { $CargoArgs } else { $RemainingArgs }
$wrapperArgs += @($finalArgs)

Push-Location $Path
try {
    Invoke-CargoWrapper @wrapperArgs
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
    Pop-Location
}
