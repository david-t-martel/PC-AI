#Requires -Version 5.1

<#
.SYNOPSIS
    PowerShell FFI wrapper for pcai-inference native Rust library using PcaiNative.dll
#>

#region Module Variables
$script:ModulePath = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.ScriptBlock.File }
$script:BackendInitialized = $false
$script:ModelLoaded = $false
$script:CurrentBackend = $null
#endregion

#region Internal Logic
function Initialize-PcaiFFI {
    # Resolve project bin
    $projectRoot = Split-Path $script:ModulePath -Parent
    $projectBin = Join-Path $projectRoot 'bin'

    # Ensure PcaiNative.dll is loaded
    $nativeDll = Join-Path $projectBin 'PcaiNative.dll'
    if (Test-Path $nativeDll) {
        try {
            [void][Reflection.Assembly]::LoadFrom($nativeDll)
            return $true
        } catch {
            Write-Warning "Failed to load $($nativeDll): $($_)"
        }
    }
    return $false
}
#endregion

#region Public Functions

function Initialize-PcaiInference {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('llamacpp', 'mistralrs')]
        [string]$Backend = 'llamacpp'
    )

    if (-not (Initialize-PcaiFFI)) {
        throw 'PcaiNative.dll not found in bin. Please run build.ps1 first.'
    }

    Write-Verbose "Initializing backend: $Backend"

    try {
        $result = [PcaiNative.InferenceModule]::pcai_init($Backend)
        if ($result -ne 0) {
            $error = [PcaiNative.InferenceModule]::GetLastError()
            throw "Failed to initialize backend '$Backend': $error"
        }

        $script:BackendInitialized = $true
        $script:CurrentBackend = $Backend
        Write-Verbose "Backend initialized successfully: $Backend"
    } catch {
        $script:BackendInitialized = $false
        throw "Backend initialization failed: $_"
    }
}

function Import-PcaiModel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelPath,

        [Parameter()]
        [int]$GpuLayers = -1
    )

    if (-not $script:BackendInitialized) {
        throw 'Backend not initialized. Call Initialize-PcaiInference first.'
    }

    if (-not (Test-Path $ModelPath)) {
        throw "Model file not found: $ModelPath"
    }

    Write-Verbose "Loading model: $ModelPath"

    try {
        $result = [PcaiNative.InferenceModule]::pcai_load_model($ModelPath, $GpuLayers)
        if ($result -ne 0) {
            $error = [PcaiNative.InferenceModule]::GetLastError()
            throw "Failed to load model: $error"
        }

        $script:ModelLoaded = $true
        Write-Verbose 'Model loaded successfully'
    } catch {
        $script:ModelLoaded = $false
        throw "Model loading failed: $_"
    }
}

function Invoke-PcaiInference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Prompt,

        [Parameter()]
        [uint32]$MaxTokens = 512,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [float]$Temperature = 0.7
    )

    if (-not $script:ModelLoaded) {
        throw 'Model not loaded. Call Import-PcaiModel first.'
    }

    try {
        $result = [PcaiNative.InferenceModule]::Generate($Prompt, $MaxTokens, $Temperature)
        if ($null -eq $result) {
            $error = [PcaiNative.InferenceModule]::GetLastError()
            throw "Generation failed: $error"
        }
        return $result
    } catch {
        throw "Inference error: $_"
    }
}

function Stop-PcaiInference {
    [CmdletBinding()]
    param()

    if ($script:BackendInitialized) {
        Write-Verbose 'Shutting down inference backend...'
        try {
            [PcaiNative.InferenceModule]::pcai_shutdown()
            $script:BackendInitialized = $false
            $script:ModelLoaded = $false
            $script:CurrentBackend = $null
        } catch {
            Write-Warning "Error during shutdown: $_"
        }
    }
}

function Get-PcaiInferenceStatus {
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        BackendInitialized = $script:BackendInitialized
        ModelLoaded        = $script:ModelLoaded
        CurrentBackend     = $script:CurrentBackend
    }
}

#endregion

#region Module Cleanup
if ($MyInvocation.MyCommand.ScriptBlock.Module) {
    $MyInvocation.MyCommand.ScriptBlock.Module.OnRemove = {
        if ($script:BackendInitialized) {
            [PcaiNative.InferenceModule]::pcai_shutdown()
        }
    }
}
#endregion

#region Module Exports
Export-ModuleMember -Function @(
    'Initialize-PcaiInference',
    'Import-PcaiModel',
    'Invoke-PcaiInference',
    'Stop-PcaiInference',
    'Get-PcaiInferenceStatus'
)
#endregion
