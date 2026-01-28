#Requires -Version 5.1

<#+
.SYNOPSIS
  Runs a Rust FunctionGemma evaluation pass and writes a metrics report.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ModelPath,
    [string]$TestData,
    [string]$Adapters,
    [string]$Output,
    [int]$MaxNewTokens = 64,
    [int]$LoraR = 16,
    [switch]$FastEval,
    [switch]$NoSchemaValidate,
    [switch]$UseLld,
    [switch]$LlmDebug
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$trainRoot = Join-Path $repoRoot 'Deploy\rust-functiongemma-train'

if (-not $ModelPath) { $ModelPath = Join-Path $repoRoot 'Models\functiongemma-270m-it' }
if (-not $TestData) { $TestData = Join-Path $repoRoot 'Deploy\functiongemma-finetune\data\rust_router_train.jsonl' }
if (-not $Output) { $Output = Join-Path $repoRoot 'Reports\functiongemma_eval_metrics.json' }

if (-not (Test-Path $ModelPath)) {
    Write-Warning "Model path not found. Skipping eval: $ModelPath"
    return
}

if (-not (Test-Path $TestData)) {
    throw "Test data not found: $TestData"
}

$parentDir = Split-Path -Parent $Output
if ($parentDir -and -not (Test-Path $parentDir)) {
    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
}

$cargoArgs = @(
    'run','--','eval',
    '--model-path', $ModelPath,
    '--test-data', $TestData,
    '--lora-r', $LoraR,
    '--max-new-tokens', $MaxNewTokens,
    '--metrics-output', $Output
)

if ($Adapters) { $cargoArgs += @('--adapters', $Adapters) }
if ($FastEval) { $cargoArgs += '--fast-eval' }
if ($NoSchemaValidate) { $cargoArgs += '--schema-validate=false' }

Write-Host "Running FunctionGemma eval..." -ForegroundColor Cyan
Write-Host "Model: $ModelPath"
Write-Host "Test Data: $TestData"
Write-Host "Metrics Output: $Output"

& (Join-Path $repoRoot 'Tools\Invoke-RustBuild.ps1') `
    -Path $trainRoot `
    -CargoArgs $cargoArgs `
    -UseLld:$UseLld `
    -LlmDebug:$LlmDebug

if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not (Test-Path $Output)) {
    throw "Eval report missing: $Output"
}

$size = (Get-Item $Output).Length
if ($size -le 0) {
    throw "Eval report is empty: $Output"
}

Write-Host "Eval report written." -ForegroundColor Green
