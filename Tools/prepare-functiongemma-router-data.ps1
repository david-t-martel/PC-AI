#Requires -Version 5.1
<#
.SYNOPSIS
  Build FunctionGemma router datasets using the Rust pipeline.

.DESCRIPTION
  Uses CargoTools via Invoke-RustBuild.ps1 to run the rust-functiongemma-train
  prepare-router command. This keeps dataset generation in Rust while matching
  the Python I/O contract (tool_calls or NO_TOOL).
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ToolsPath,
    [string]$DiagnosePrompt,
    [string]$ChatPrompt,
    [string]$ScenariosPath,
    [string]$Output,
    [string]$TestVectors,
    [int]$MaxCases = 24,
    [switch]$NoToolCoverage,
    [switch]$UseLld,
    [switch]$LlmDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainRoot = Join-Path $repoRoot 'Deploy\rust-functiongemma-train'

if (-not $ToolsPath) { $ToolsPath = Join-Path $repoRoot 'Config\pcai-tools.json' }
if (-not $DiagnosePrompt) { $DiagnosePrompt = Join-Path $repoRoot 'DIAGNOSE.md' }
if (-not $ChatPrompt) { $ChatPrompt = Join-Path $repoRoot 'CHAT.md' }
if (-not $ScenariosPath) { $ScenariosPath = Join-Path $repoRoot 'Deploy\functiongemma-finetune\scenarios.json' }
if (-not $Output) { $Output = Join-Path $repoRoot 'Deploy\functiongemma-finetune\data\rust_router_train.jsonl' }
if (-not $TestVectors) { $TestVectors = Join-Path $repoRoot 'Deploy\functiongemma-finetune\test_vectors.json' }

Write-Host "Preparing FunctionGemma router dataset (Rust)..." -ForegroundColor Cyan
Write-Host "Tools: $ToolsPath"
Write-Host "Output: $Output"
Write-Host "TestVectors: $TestVectors"

$cargoArgs = @(
    'run','--','prepare-router',
    '--tools', $ToolsPath,
    '--output', $Output,
    '--diagnose-prompt', $DiagnosePrompt,
    '--chat-prompt', $ChatPrompt,
    '--max-cases', $MaxCases
)

if ($ScenariosPath) { $cargoArgs += @('--scenarios', $ScenariosPath) }
if ($NoToolCoverage) { $cargoArgs += '--no-tool-coverage' }
if ($TestVectors) { $cargoArgs += @('--test-vectors', $TestVectors) }

& (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') `
    -Path $trainRoot `
    -CargoArgs $cargoArgs `
    -UseLld:$UseLld `
    -LlmDebug:$LlmDebug

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Router dataset generation complete." -ForegroundColor Green
