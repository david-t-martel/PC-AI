#Requires -Version 5.1

<#
.SYNOPSIS
    Test script for native Rust inference integration

.DESCRIPTION
    Demonstrates and tests the integration of pcai-inference with PC-AI.ps1.
    Tests both FFI module loading and PC-AI.ps1 backend routing.

.NOTES
    Prerequisites:
    1. Build the DLL:
       cd Deploy\pcai-inference
       cargo build --features ffi,mistralrs-backend --release

    2. Have a GGUF model file available (e.g., from Ollama's model directory)
#>

param(
    [Parameter()]
    [string]$ModelPath = $null,

    [Parameter()]
    [switch]$SkipModuleTest,

    [Parameter()]
    [switch]$SkipIntegrationTest
)

$ErrorActionPreference = 'Stop'
$VerbosePreference = 'Continue'

Write-Host "`n=== PC-AI Native Inference Test Suite ===" -ForegroundColor Cyan
Write-Host ""

#region DLL Check
Write-Host "Step 1: Checking for DLL..." -ForegroundColor Yellow
$dllPath = Join-Path $PSScriptRoot 'Deploy\pcai-inference\target\release\pcai_inference.dll'

if (Test-Path $dllPath) {
    Write-Host "  DLL found: $dllPath" -ForegroundColor Green
    $dllExists = $true
}
else {
    Write-Host "  DLL not found: $dllPath" -ForegroundColor Red
    Write-Host ""
    Write-Host "Build instructions:" -ForegroundColor Yellow
    Write-Host "  cd Deploy\pcai-inference" -ForegroundColor Gray
    Write-Host "  cargo build --features ffi,mistralrs-backend --release" -ForegroundColor Gray
    Write-Host ""
    $dllExists = $false
}
#endregion

#region Module Test
if (-not $SkipModuleTest) {
    Write-Host "`nStep 2: Testing PcaiInference module..." -ForegroundColor Yellow

    try {
        Import-Module (Join-Path $PSScriptRoot 'Modules\PcaiInference.psm1') -Force
        Write-Host "  Module loaded successfully" -ForegroundColor Green

        $commands = Get-Command -Module PcaiInference
        Write-Host "  Exported functions:" -ForegroundColor Gray
        $commands | ForEach-Object {
            Write-Host "    - $($_.Name)" -ForegroundColor Gray
        }

        # Test status function
        Write-Host "`n  Testing Get-PcaiInferenceStatus..." -ForegroundColor Gray
        $status = Get-PcaiInferenceStatus
        Write-Host "    DLL Path: $($status.DllPath)" -ForegroundColor Gray
        Write-Host "    DLL Exists: $($status.DllExists)" -ForegroundColor $(if ($status.DllExists) { 'Green' } else { 'Red' })
        Write-Host "    Backend Initialized: $($status.BackendInitialized)" -ForegroundColor Gray
        Write-Host "    Model Loaded: $($status.ModelLoaded)" -ForegroundColor Gray
    }
    catch {
        Write-Host "  Module test failed: $_" -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Integration Test
if (-not $SkipIntegrationTest) {
    Write-Host "`nStep 3: Testing PC-AI.ps1 integration..." -ForegroundColor Yellow

    try {
        Write-Host "  Testing status command (default HTTP mode)..." -ForegroundColor Gray
        & (Join-Path $PSScriptRoot 'PC-AI.ps1') status -Verbose:$false | Out-String | Write-Host

        if ($dllExists) {
            Write-Host "`n  Testing with -UseNativeInference flag..." -ForegroundColor Gray

            if ($ModelPath -and (Test-Path $ModelPath)) {
                Write-Host "  Model path: $ModelPath" -ForegroundColor Gray
                & (Join-Path $PSScriptRoot 'PC-AI.ps1') status -UseNativeInference -ModelPath $ModelPath -Verbose | Out-String | Write-Host
            }
            else {
                Write-Host "  No model path provided, testing without model load..." -ForegroundColor Gray
                & (Join-Path $PSScriptRoot 'PC-AI.ps1') status -UseNativeInference -Verbose | Out-String | Write-Host
            }
        }
        else {
            Write-Host "  Skipping native inference test (DLL not built)" -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  Integration test failed: $_" -ForegroundColor Red
        exit 1
    }
}
#endregion

#region Full Workflow Example
if ($dllExists -and $ModelPath -and (Test-Path $ModelPath)) {
    Write-Host "`nStep 4: Full workflow test (with model)..." -ForegroundColor Yellow

    try {
        Write-Host "  Initializing backend..." -ForegroundColor Gray
        Import-Module (Join-Path $PSScriptRoot 'Modules\PcaiInference.psm1') -Force

        Initialize-PcaiInference -Backend mistralrs -Verbose

        Write-Host "  Loading model..." -ForegroundColor Gray
        Import-PcaiModel -ModelPath $ModelPath -GpuLayers -1 -Verbose

        Write-Host "  Running test inference..." -ForegroundColor Gray
        $result = Invoke-PcaiGenerate -Prompt "Respond with 'OK' only." -MaxTokens 10 -Temperature 0.0 -Verbose

        Write-Host "  Response: $result" -ForegroundColor Green

        Write-Host "  Cleaning up..." -ForegroundColor Gray
        Close-PcaiInference -Verbose

        Write-Host "`n  Full workflow test passed!" -ForegroundColor Green
    }
    catch {
        Write-Host "  Full workflow test failed: $_" -ForegroundColor Red
        Close-PcaiInference -ErrorAction SilentlyContinue
        exit 1
    }
}
else {
    Write-Host "`nStep 4: Skipping full workflow test" -ForegroundColor Yellow
    if (-not $dllExists) {
        Write-Host "  Reason: DLL not built" -ForegroundColor Gray
    }
    if (-not $ModelPath) {
        Write-Host "  Reason: No model path provided (use -ModelPath)" -ForegroundColor Gray
    }
    if ($ModelPath -and -not (Test-Path $ModelPath)) {
        Write-Host "  Reason: Model file not found: $ModelPath" -ForegroundColor Gray
    }
}
#endregion

Write-Host "`n=== Test Suite Complete ===" -ForegroundColor Cyan
Write-Host ""

#region Usage Examples
Write-Host "Usage Examples:" -ForegroundColor Yellow
Write-Host ""
Write-Host "1. Status with HTTP backend (default):" -ForegroundColor Gray
Write-Host "   .\PC-AI.ps1 status" -ForegroundColor White
Write-Host ""
Write-Host "2. Status with native inference (auto backend):" -ForegroundColor Gray
Write-Host "   .\PC-AI.ps1 status -UseNativeInference -ModelPath 'C:\models\phi3.gguf'" -ForegroundColor White
Write-Host ""
Write-Host "3. Specific backend selection:" -ForegroundColor Gray
Write-Host "   .\PC-AI.ps1 status -InferenceBackend mistralrs -ModelPath 'C:\models\phi3.gguf'" -ForegroundColor White
Write-Host ""
Write-Host "4. Direct module usage:" -ForegroundColor Gray
Write-Host "   Import-Module .\Modules\PcaiInference.psm1" -ForegroundColor White
Write-Host "   Initialize-PcaiInference -Backend mistralrs" -ForegroundColor White
Write-Host "   Import-PcaiModel -ModelPath 'C:\models\phi3.gguf'" -ForegroundColor White
Write-Host "   Invoke-PcaiGenerate -Prompt 'Hello!'" -ForegroundColor White
Write-Host "   Close-PcaiInference" -ForegroundColor White
Write-Host ""
#endregion
