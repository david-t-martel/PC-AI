#Requires -Version 5.1
<#
.SYNOPSIS
  Build token cache for FunctionGemma training (Rust).

.DESCRIPTION
  Uses rust-functiongemma-train prepare-cache to pre-tokenize JSONL datasets.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Input,
    [string]$TokenizerPath,
    [string]$OutputDir,
    [switch]$UseLld,
    [switch]$LlmDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainRoot = Join-Path $repoRoot 'Deploy\rust-functiongemma-train'

if (-not $Input) { $Input = Join-Path $repoRoot 'Deploy\functiongemma-finetune\data\rust_router_train.jsonl' }
if (-not $TokenizerPath) { $TokenizerPath = Join-Path $repoRoot 'Models\functiongemma-270m-it\tokenizer.json' }
if (-not $OutputDir) { $OutputDir = Join-Path $repoRoot 'output\functiongemma-token-cache' }

$cargoArgs = @(
    'run','--','prepare-cache',
    '--input', $Input,
    '--tokenizer', $TokenizerPath,
    '--output-dir', $OutputDir
)

& (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') `
    -Path $trainRoot `
    -CargoArgs $cargoArgs `
    -UseLld:$UseLld `
    -LlmDebug:$LlmDebug

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "Token cache built at $OutputDir" -ForegroundColor Green
