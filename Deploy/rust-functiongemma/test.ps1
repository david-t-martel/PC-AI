#Requires -Version 5.1
<#
.SYNOPSIS
  Test Rust FunctionGemma runtime + training pipeline.

.DESCRIPTION
  Pass/Fail criteria:
  1) rust-functiongemma-runtime tests pass.
  2) rust-functiongemma-train tests pass.
  3) Router dataset JSONL + tool test vectors exist and are non-empty.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$IncludeRuntime = $true,
    [switch]$Fast,
    [switch]$EvalReport
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimePath = Join-Path $repoRoot 'Deploy\rust-functiongemma-runtime'

if ($IncludeRuntime) {
    Write-Host "Running runtime tests..." -ForegroundColor Cyan
    & (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') -Path $runtimePath test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "Running training + dataset tests..." -ForegroundColor Cyan
& (Join-Path $repoRoot 'Tools\run-functiongemma-tests.ps1') -Category rust -Runtime rust -Fast:$Fast -EvalReport:$EvalReport -EvalFast:$Fast
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "All Rust FunctionGemma tests passed." -ForegroundColor Green
