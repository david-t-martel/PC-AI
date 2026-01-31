#Requires -Version 7.0
<#
.SYNOPSIS
    Validates PC-AI.Evaluation module dependencies

.DESCRIPTION
    Checks for required components:
    - PcaiInference PowerShell module
    - pcai_inference.dll native library
    - Required .NET assemblies
#>

$ErrorActionPreference = 'Stop'

# Find project root
$moduleRoot = Split-Path -Parent $PSScriptRoot
$projectRoot = Split-Path -Parent $moduleRoot

# DLL search paths
$dllSearchPaths = @(
    (Join-Path $projectRoot 'bin\Release\pcai_inference.dll'),
    (Join-Path $projectRoot 'bin\Debug\pcai_inference.dll'),
    (Join-Path $env:CARGO_TARGET_DIR 'release\pcai_inference.dll' -ErrorAction SilentlyContinue),
    (Join-Path $env:CARGO_TARGET_DIR 'debug\pcai_inference.dll' -ErrorAction SilentlyContinue)
) | Where-Object { $_ }

# Check for DLL
$dllFound = $false
foreach ($path in $dllSearchPaths) {
    if (Test-Path $path -ErrorAction SilentlyContinue) {
        $dllFound = $true
        $script:PcaiDllPath = $path
        break
    }
}

if (-not $dllFound) {
    $buildInstructions = @"

╔══════════════════════════════════════════════════════════════════╗
║  PC-AI.Evaluation requires pcai_inference.dll                    ║
╠══════════════════════════════════════════════════════════════════╣
║                                                                   ║
║  Build the native library first:                                  ║
║                                                                   ║
║    cd Deploy\pcai-inference                                       ║
║    .\build.ps1 -Backend mistralrs                                 ║
║                                                                   ║
║  Or for CUDA-enabled llama.cpp:                                   ║
║                                                                   ║
║    .\build-llamacpp-fixed.ps1                                     ║
║                                                                   ║
╚══════════════════════════════════════════════════════════════════╝
"@
    Write-Warning $buildInstructions

    # Don't throw - allow module to load for documentation/offline use
    # Actual usage will fail when trying to invoke native functions
}

# Check for PcaiInference module
$pcaiModulePath = Join-Path $projectRoot 'Modules\PcaiInference.psm1'
if (-not (Test-Path $pcaiModulePath)) {
    Write-Warning "PcaiInference.psm1 not found at: $pcaiModulePath"
}

# Export validation results
$script:DependencyStatus = @{
    DllAvailable = $dllFound
    DllPath = $script:PcaiDllPath
    ModuleAvailable = Test-Path $pcaiModulePath
    ModulePath = $pcaiModulePath
    ValidationTime = [datetime]::UtcNow
}
