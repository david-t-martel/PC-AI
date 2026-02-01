# Example: Using pcai-inference from PowerShell via FFI
#
# This script demonstrates how to call the Rust FFI functions from PowerShell
# to perform LLM inference directly without going through HTTP.
#
# Prerequisites:
# 1. Build the library: cargo build --features ffi,mistralrs-backend --release
# 2. The DLL will be at: target\release\pcai_inference.dll
# 3. Have a model file ready (GGUF or SafeTensors format)

using namespace System.Runtime.InteropServices

# Define the FFI function signatures
Add-Type @"
using System;
using System.Runtime.InteropServices;

public class PCAIInference {
    private const string DLL_PATH = @"target\release\pcai_inference.dll";

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

# Configuration
$BackendName = "mistralrs"  # or "llamacpp"
$ModelPath = "C:\models\phi-3-mini.gguf"  # Update with your model path
$GpuLayers = -1  # -1 = all layers to GPU, 0 = CPU only

function Invoke-PCAIInference {
    param(
        [string]$Prompt,
        [int]$MaxTokens = 512,
        [float]$Temperature = 0.7
    )

    try {
        # Generate text
        $resultPtr = [PCAIInference]::pcai_generate($Prompt, $MaxTokens, $Temperature)

        if ($resultPtr -eq [IntPtr]::Zero) {
            $error = [PCAIInference]::GetLastError()
            throw "Generation failed: $error"
        }

        # Convert to string
        $result = [Marshal]::PtrToStringUTF8($resultPtr)

        # Free the string
        [PCAIInference]::pcai_free_string($resultPtr)

        return $result
    }
    catch {
        Write-Error "Inference error: $_"
        $error = [PCAIInference]::GetLastError()
        if ($error) {
            Write-Error "Backend error: $error"
        }
        return $null
    }
}

# Main execution
try {
    Write-Host "Initializing PCAI Inference..." -ForegroundColor Cyan

    # Initialize backend
    $result = [PCAIInference]::pcai_init($BackendName)
    if ($result -ne 0) {
        $error = [PCAIInference]::GetLastError()
        throw "Failed to initialize backend: $error"
    }
    Write-Host "Backend initialized: $BackendName" -ForegroundColor Green

    # Load model
    Write-Host "Loading model: $ModelPath" -ForegroundColor Cyan
    $result = [PCAIInference]::pcai_load_model($ModelPath, $GpuLayers)
    if ($result -ne 0) {
        $error = [PCAIInference]::GetLastError()
        throw "Failed to load model: $error"
    }
    Write-Host "Model loaded successfully" -ForegroundColor Green

    # Run inference
    Write-Host "`nRunning inference..." -ForegroundColor Cyan
    $prompt = "Explain what PowerShell is in one sentence:"
    Write-Host "Prompt: $prompt" -ForegroundColor Yellow

    $response = Invoke-PCAIInference -Prompt $prompt -MaxTokens 100 -Temperature 0.7

    if ($response) {
        Write-Host "`nResponse:" -ForegroundColor Green
        Write-Host $response
    }

    # Example: Multiple prompts
    Write-Host "`nRunning second inference..." -ForegroundColor Cyan
    $prompt2 = "What is Rust programming language?"
    Write-Host "Prompt: $prompt2" -ForegroundColor Yellow

    $response2 = Invoke-PCAIInference -Prompt $prompt2 -MaxTokens 150 -Temperature 0.5

    if ($response2) {
        Write-Host "`nResponse:" -ForegroundColor Green
        Write-Host $response2
    }
}
catch {
    Write-Error "Fatal error: $_"
}
finally {
    # Cleanup
    Write-Host "`nShutting down..." -ForegroundColor Cyan
    [PCAIInference]::pcai_shutdown()
    Write-Host "Done" -ForegroundColor Green
}
