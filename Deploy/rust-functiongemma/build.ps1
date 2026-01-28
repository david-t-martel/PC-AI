#Requires -Version 5.1
<#
.SYNOPSIS
  Build Rust FunctionGemma runtime + training crates.

.DESCRIPTION
  Uses CargoTools via Tools/Invoke-RustBuild.ps1 to build both crates.
  Pass/Fail: exits non-zero if any build fails.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [switch]$Release,
    [switch]$UseLld,
    [switch]$LlmDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$runtimePath = Join-Path $repoRoot 'Deploy\rust-functiongemma-runtime'
$trainPath = Join-Path $repoRoot 'Deploy\rust-functiongemma-train'

$buildArgs = @('build')
if ($Release) { $buildArgs += '--release' }

Write-Host "Building rust-functiongemma-runtime..." -ForegroundColor Cyan
& (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') -Path $runtimePath -CargoArgs $buildArgs -UseLld:$UseLld -LlmDebug:$LlmDebug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Building rust-functiongemma-train..." -ForegroundColor Cyan
& (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') -Path $trainPath -CargoArgs $buildArgs -UseLld:$UseLld -LlmDebug:$LlmDebug
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Build complete." -ForegroundColor Green
