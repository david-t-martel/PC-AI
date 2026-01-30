#Requires -Version 5.1

<#
.SYNOPSIS
    PowerShell FFI wrapper for pcai-inference native Rust library

.DESCRIPTION
    Provides P/Invoke bindings to the pcai-inference DLL for direct LLM inference
    without HTTP overhead. Supports llamacpp and mistralrs backends.

.NOTES
    Author: PC_AI Framework
    Version: 1.0.0
    Requires: Deploy\pcai-inference\target\release\pcai_inference.dll
#>

using namespace System.Runtime.InteropServices

#region Module Variables
$script:DllPath = $null
$script:BackendInitialized = $false
$script:ModelLoaded = $false
$script:CurrentBackend = $null
#endregion

#region P/Invoke Type Definition
function Initialize-PcaiFFI {
    <#
    .SYNOPSIS
        Loads the FFI type definitions for pcai-inference
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DllPath
    )

    # Check if DLL exists
    if (-not (Test-Path $DllPath)) {
        throw "DLL not found: $DllPath`n`nBuild instructions:`n  cd Deploy\pcai-inference`n  cargo build --features ffi,mistralrs-backend --release"
    }

    try {
        Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PcaiInferenceFFI {
    private const string DLL_PATH = @"$DllPath";

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern int pcai_init(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string backend_name
    );

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern int pcai_load_model(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string model_path,
        int gpu_layers
    );

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr pcai_generate(
        [MarshalAs(UnmanagedType.LPUTF8Str)] string prompt,
        uint max_tokens,
        float temperature
    );

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_free_string(IntPtr str);

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern void pcai_shutdown();

    [DllImport(DLL_PATH, CallingConvention = CallingConvention.Cdecl)]
    public static extern IntPtr pcai_last_error();

    // Helper to get error message
    public static string GetLastError() {
        IntPtr errPtr = pcai_last_error();
        if (errPtr == IntPtr.Zero) {
            return null;
        }
        return Marshal.PtrToStringUTF8(errPtr);
    }
}
"@
        Write-Verbose "FFI type definitions loaded successfully"
    }
    catch {
        throw "Failed to load FFI type definitions: $_"
    }
}
#endregion

#region Public Functions

function Initialize-PcaiInference {
    <#
    .SYNOPSIS
        Initialize the pcai-inference backend

    .DESCRIPTION
        Initializes the specified inference backend (llamacpp or mistralrs).
        Must be called before loading a model.

    .PARAMETER Backend
        Backend to initialize: llamacpp, mistralrs, or auto (attempts mistralrs first)

    .PARAMETER DllPath
        Path to pcai_inference.dll (defaults to Deploy\pcai-inference\target\release\pcai_inference.dll)

    .EXAMPLE
        Initialize-PcaiInference -Backend mistralrs -Verbose

    .EXAMPLE
        Initialize-PcaiInference -Backend auto
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('llamacpp', 'mistralrs', 'auto')]
        [string]$Backend = 'auto',

        [Parameter()]
        [string]$DllPath = $null
    )

    # Resolve DLL path
    if (-not $DllPath) {
        $projectRoot = Split-Path $PSScriptRoot -Parent
        $DllPath = Join-Path $projectRoot 'Deploy\pcai-inference\target\release\pcai_inference.dll'
    }

    $script:DllPath = $DllPath

    # Load FFI definitions if not already loaded
    if (-not ([System.Management.Automation.PSTypeName]'PcaiInferenceFFI').Type) {
        Write-Verbose "Loading FFI type definitions..."
        Initialize-PcaiFFI -DllPath $DllPath
    }

    # Auto-detect backend
    if ($Backend -eq 'auto') {
        Write-Verbose "Auto-detecting backend..."
        $Backend = 'mistralrs'  # Prefer mistralrs on Windows
        Write-Verbose "Selected backend: $Backend"
    }

    Write-Verbose "Initializing backend: $Backend"

    try {
        $result = [PcaiInferenceFFI]::pcai_init($Backend)

        if ($result -ne 0) {
            $error = [PcaiInferenceFFI]::GetLastError()
            throw "Failed to initialize backend '$Backend': $error"
        }

        $script:BackendInitialized = $true
        $script:CurrentBackend = $Backend
        Write-Verbose "Backend initialized successfully: $Backend"

        return @{
            Success = $true
            Backend = $Backend
        }
    }
    catch {
        $script:BackendInitialized = $false
        throw "Backend initialization failed: $_"
    }
}

function Import-PcaiModel {
    <#
    .SYNOPSIS
        Load a model into the inference backend

    .DESCRIPTION
        Loads a GGUF or SafeTensors model file into the initialized backend.
        Requires Initialize-PcaiInference to be called first.

    .PARAMETER ModelPath
        Path to the model file (GGUF or SafeTensors format)

    .PARAMETER GpuLayers
        Number of layers to offload to GPU (-1 = all layers, 0 = CPU only)

    .EXAMPLE
        Import-PcaiModel -ModelPath "C:\models\phi-3-mini.gguf" -GpuLayers -1

    .EXAMPLE
        Import-PcaiModel -ModelPath "$env:USERPROFILE\.ollama\models\phi3.gguf"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ModelPath,

        [Parameter()]
        [int]$GpuLayers = -1
    )

    if (-not $script:BackendInitialized) {
        throw "Backend not initialized. Call Initialize-PcaiInference first."
    }

    if (-not (Test-Path $ModelPath)) {
        throw "Model file not found: $ModelPath"
    }

    Write-Verbose "Loading model: $ModelPath"
    Write-Verbose "GPU layers: $GpuLayers"

    try {
        $result = [PcaiInferenceFFI]::pcai_load_model($ModelPath, $GpuLayers)

        if ($result -ne 0) {
            $error = [PcaiInferenceFFI]::GetLastError()
            throw "Failed to load model: $error"
        }

        $script:ModelLoaded = $true
        Write-Verbose "Model loaded successfully"

        return @{
            Success = $true
            ModelPath = $ModelPath
            GpuLayers = $GpuLayers
        }
    }
    catch {
        $script:ModelLoaded = $false
        throw "Model loading failed: $_"
    }
}

function Invoke-PcaiGenerate {
    <#
    .SYNOPSIS
        Generate text using the loaded model

    .DESCRIPTION
        Generates text from the specified prompt using the loaded model.
        Requires both Initialize-PcaiInference and Import-PcaiModel to be called first.

    .PARAMETER Prompt
        Input text prompt

    .PARAMETER MaxTokens
        Maximum number of tokens to generate (default: 512)

    .PARAMETER Temperature
        Sampling temperature (0.0 = greedy, higher = more random)

    .EXAMPLE
        Invoke-PcaiGenerate -Prompt "Explain PowerShell in one sentence:" -MaxTokens 100

    .EXAMPLE
        Invoke-PcaiGenerate -Prompt "What is Rust?" -Temperature 0.7 -MaxTokens 150
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,

        [Parameter()]
        [int]$MaxTokens = 512,

        [Parameter()]
        [ValidateRange(0.0, 2.0)]
        [float]$Temperature = 0.7
    )

    if (-not $script:BackendInitialized) {
        throw "Backend not initialized. Call Initialize-PcaiInference first."
    }

    if (-not $script:ModelLoaded) {
        throw "Model not loaded. Call Import-PcaiModel first."
    }

    Write-Verbose "Generating with prompt: $($Prompt.Substring(0, [Math]::Min(50, $Prompt.Length)))..."
    Write-Verbose "Max tokens: $MaxTokens, Temperature: $Temperature"

    try {
        $resultPtr = [PcaiInferenceFFI]::pcai_generate($Prompt, $MaxTokens, $Temperature)

        if ($resultPtr -eq [IntPtr]::Zero) {
            $error = [PcaiInferenceFFI]::GetLastError()
            throw "Generation failed: $error"
        }

        # Convert to string
        $result = [Marshal]::PtrToStringUTF8($resultPtr)

        # Free the string
        [PcaiInferenceFFI]::pcai_free_string($resultPtr)

        Write-Verbose "Generation completed successfully"
        return $result
    }
    catch {
        $error = [PcaiInferenceFFI]::GetLastError()
        if ($error) {
            throw "Inference error: $error"
        }
        throw "Inference error: $_"
    }
}

function Close-PcaiInference {
    <#
    .SYNOPSIS
        Shutdown the inference backend and free resources

    .DESCRIPTION
        Unloads the model and cleans up backend resources.
        After calling this, you must call Initialize-PcaiInference again to use inference.

    .EXAMPLE
        Close-PcaiInference -Verbose
    #>
    [CmdletBinding()]
    param()

    if (-not $script:BackendInitialized) {
        Write-Verbose "Backend not initialized, nothing to close"
        return
    }

    Write-Verbose "Shutting down inference backend..."

    try {
        [PcaiInferenceFFI]::pcai_shutdown()
        $script:BackendInitialized = $false
        $script:ModelLoaded = $false
        $script:CurrentBackend = $null
        Write-Verbose "Backend shutdown successfully"
    }
    catch {
        Write-Warning "Error during shutdown: $_"
    }
}

function Get-PcaiInferenceStatus {
    <#
    .SYNOPSIS
        Get the current status of the inference backend

    .DESCRIPTION
        Returns information about the current state of the inference backend.

    .EXAMPLE
        Get-PcaiInferenceStatus
    #>
    [CmdletBinding()]
    param()

    return [PSCustomObject]@{
        DllPath = $script:DllPath
        DllExists = if ($script:DllPath) { Test-Path $script:DllPath } else { $false }
        BackendInitialized = $script:BackendInitialized
        ModelLoaded = $script:ModelLoaded
        CurrentBackend = $script:CurrentBackend
    }
}

function Test-PcaiInference {
    <#
    .SYNOPSIS
        Test the inference backend with a simple prompt

    .DESCRIPTION
        Performs a quick test of the inference backend to verify it's working.
        Requires backend initialization and model loading.

    .EXAMPLE
        Test-PcaiInference -Verbose
    #>
    [CmdletBinding()]
    param()

    Write-Host "Testing inference backend..." -ForegroundColor Cyan

    $status = Get-PcaiInferenceStatus

    Write-Host "  DLL Path: $($status.DllPath)" -ForegroundColor Gray
    Write-Host "  DLL Exists: $($status.DllExists)" -ForegroundColor $(if ($status.DllExists) { 'Green' } else { 'Red' })
    Write-Host "  Backend Initialized: $($status.BackendInitialized)" -ForegroundColor $(if ($status.BackendInitialized) { 'Green' } else { 'Yellow' })
    Write-Host "  Model Loaded: $($status.ModelLoaded)" -ForegroundColor $(if ($status.ModelLoaded) { 'Green' } else { 'Yellow' })
    Write-Host "  Current Backend: $($status.CurrentBackend)" -ForegroundColor Gray

    if (-not $status.BackendInitialized -or -not $status.ModelLoaded) {
        Write-Warning "Backend not ready for inference"
        return $false
    }

    Write-Host "`nRunning test inference..." -ForegroundColor Cyan
    $testPrompt = "Respond with 'OK' only."

    try {
        $result = Invoke-PcaiGenerate -Prompt $testPrompt -MaxTokens 10 -Temperature 0.0
        Write-Host "  Response: $result" -ForegroundColor Green
        Write-Host "`nTest passed!" -ForegroundColor Green
        return $true
    }
    catch {
        Write-Host "  Test failed: $_" -ForegroundColor Red
        return $false
    }
}

#endregion

#region Module Exports
Export-ModuleMember -Function @(
    'Initialize-PcaiInference',
    'Import-PcaiModel',
    'Invoke-PcaiGenerate',
    'Close-PcaiInference',
    'Get-PcaiInferenceStatus',
    'Test-PcaiInference'
)
#endregion
