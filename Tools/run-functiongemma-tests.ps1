#Requires -Version 5.1

<#+
.SYNOPSIS
  Runs FunctionGemma fine-tuning test suite and tool coverage reports.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('unit','integration','e2e','functional','all')]
    [string]$Category = 'unit'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$fgRoot = Join-Path $repoRoot 'Deploy\functiongemma-finetune'

& (Join-Path $repoRoot 'Tools\update-doc-status.ps1') -RepoRoot $repoRoot | Out-Null
& (Join-Path $repoRoot 'Tools\update-tool-coverage.ps1') -RepoRoot $repoRoot | Out-Null

$pytestArgs = @('-m', $Category)
if ($Category -eq 'all') { $pytestArgs = @() }

Push-Location $fgRoot
try {
    $env:PYTHONUTF8 = '1'
    if (-not $env:VLLM_BASE_URL) { $env:VLLM_BASE_URL = 'http://127.0.0.1:8000' }

    # Use uv if available, fallback to python.
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    if ($uv) {
        & uv run python -m pytest @pytestArgs .
    } else {
        & python -m pytest @pytestArgs .
    }
}
finally {
    Pop-Location
}
