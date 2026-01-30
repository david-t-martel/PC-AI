# Native Rust Inference Integration

## Overview

PC-AI now supports dual-mode inference:
- **HTTP Mode** (default): Uses Ollama/vLLM/LM Studio via REST API
- **Native Mode**: Direct FFI calls to pcai-inference Rust library

This integration provides:
- Zero HTTP overhead for local inference
- GPU acceleration via CUDA (mistralrs) or CPU fallback
- Graceful degradation to HTTP if native backend unavailable
- Consistent API across both modes

## Architecture

```
┌─────────────────┐
│   PC-AI.ps1     │
│  Entry Point    │
└────────┬────────┘
         │
         ├──── HTTP Mode ────> Ollama/vLLM (REST API)
         │                     ↓
         │                 [LLM Server]
         │
         └──── Native Mode ──> PcaiInference.psm1
                                ↓
                          [pcai_inference.dll]
                                ↓
                          [llamacpp / mistralrs]
                                ↓
                          [GGUF Model File]
```

## Components

### 1. Modules/PcaiInference.psm1

PowerShell module providing P/Invoke bindings to the Rust FFI.

**Key Functions:**
- `Initialize-PcaiInference` - Initialize backend (llamacpp/mistralrs)
- `Import-PcaiModel` - Load GGUF or SafeTensors model
- `Invoke-PcaiGenerate` - Generate text synchronously
- `Close-PcaiInference` - Cleanup resources
- `Get-PcaiInferenceStatus` - Query backend state
- `Test-PcaiInference` - Verify functionality

**FFI Bindings:**
```csharp
[DllImport("pcai_inference.dll")]
extern int pcai_init(string backend_name);
extern int pcai_load_model(string model_path, int gpu_layers);
extern IntPtr pcai_generate(string prompt, uint max_tokens, float temperature);
extern void pcai_free_string(IntPtr str);
extern void pcai_shutdown();
extern IntPtr pcai_last_error();
```

### 2. PC-AI.ps1 Integration

**New Parameters:**
```powershell
-InferenceBackend <auto|llamacpp|mistralrs|http>
-ModelPath <path-to-gguf-file>
-GpuLayers <int>  # -1 = all, 0 = CPU only
-UseNativeInference
```

**Backend Selection Logic:**
1. If `-InferenceBackend http` → Use HTTP mode
2. If `-UseNativeInference` or specific backend → Attempt native
3. Native initialization:
   - Check DLL exists
   - Initialize backend
   - Load model (if `-ModelPath` provided)
   - Fall back to HTTP on any failure
4. Cleanup on script exit via `finally` block

### 3. Deploy/pcai-inference

Rust crate providing the FFI layer.

**Build Command:**
```bash
cd Deploy/pcai-inference
cargo build --features ffi,mistralrs-backend --release
```

**Output:** `target/release/pcai_inference.dll`

**Backends:**
- **mistralrs** (recommended): Better Windows support, CUDA integration
- **llamacpp**: Cross-platform, streaming support

## Usage Examples

### Quick Start

```powershell
# Build the DLL first
cd Deploy\pcai-inference
cargo build --features ffi,mistralrs-backend --release

# Test module loading
Import-Module .\Modules\PcaiInference.psm1
Get-PcaiInferenceStatus

# Initialize and test
Initialize-PcaiInference -Backend mistralrs -Verbose
Import-PcaiModel -ModelPath "C:\models\phi-3-mini.gguf" -GpuLayers -1
$result = Invoke-PcaiGenerate -Prompt "What is PowerShell?" -MaxTokens 100
Write-Host $result
Close-PcaiInference
```

### PC-AI.ps1 Integration

```powershell
# Default HTTP mode (no changes needed)
.\PC-AI.ps1 status

# Native inference with auto backend
.\PC-AI.ps1 status -UseNativeInference -ModelPath "C:\models\phi3.gguf"

# Specific backend selection
.\PC-AI.ps1 analyze -InferenceBackend mistralrs -ModelPath "C:\models\phi3.gguf" -GpuLayers -1

# Analyze diagnostic report with native inference
.\PC-AI.ps1 diagnose all
.\PC-AI.ps1 analyze -UseNativeInference -ModelPath "C:\models\qwen2.5-coder-7b.gguf"
```

### Chat with Native Inference

```powershell
# Start chat session with native backend
.\PC-AI.ps1 chat -UseNativeInference -ModelPath "C:\models\phi3.gguf"
```

## Configuration

### Config/llm-config.json

Existing HTTP providers remain unchanged:
```json
{
  "providers": {
    "ollama": {
      "enabled": true,
      "baseUrl": "hvsock://ollama",
      "defaultModel": "qwen2.5-coder:7b"
    }
  }
}
```

Native inference is configured via command-line parameters, not config file.

### Model Path Discovery

Common model locations:
- Ollama: `$env:USERPROFILE\.ollama\models\blobs\sha256-*`
- LM Studio: `$env:USERPROFILE\.cache\lm-studio\models\`
- Custom: Any accessible GGUF file path

## Performance Considerations

### Benchmarks (Preliminary)

| Mode | Overhead | Throughput | Latency |
|------|----------|------------|---------|
| HTTP (Ollama) | ~5-10ms/request | Varies by model | Network + server queue |
| Native FFI | ~0.1ms/call | Model-dependent | Direct, no queue |

**Optimization Tips:**
1. Keep model loaded across multiple inferences
2. Use `-GpuLayers -1` for full GPU acceleration
3. Batch prompts when possible
4. Consider model size vs. available VRAM

### Resource Usage

- **DLL Size:** ~50-100 MB (includes mistralrs dependencies)
- **Model Loading:** One-time cost, ~1-5 seconds depending on model size
- **Memory:** Model size + ~500 MB overhead for mistralrs runtime
- **GPU VRAM:** Model layers * layer size (GGUF quantization reduces this)

## Error Handling

### Graceful Fallback

```powershell
# Missing DLL
PS> .\PC-AI.ps1 status -UseNativeInference
WARNING: pcai_inference.dll not found. Build instructions:
WARNING:   cd Deploy\pcai-inference
WARNING:   cargo build --features ffi,mistralrs-backend --release
WARNING: Falling back to HTTP inference.
# Continues with HTTP mode

# Model load failure
PS> Initialize-PcaiInference -Backend mistralrs
PS> Import-PcaiModel -ModelPath "invalid.gguf"
ERROR: Failed to load model: File not found
# Script can still use HTTP mode
```

### Error Retrieval

FFI errors are retrieved via `pcai_last_error()`:
```powershell
try {
    $result = Invoke-PcaiGenerate -Prompt "test"
} catch {
    Write-Error "Generation failed: $_"
    # Detailed error already retrieved from FFI
}
```

## Testing

### Test Suite

```powershell
# Run comprehensive tests
.\Test-NativeInference.ps1 -Verbose

# Test with specific model
.\Test-NativeInference.ps1 -ModelPath "C:\models\phi3.gguf"

# Skip integration tests
.\Test-NativeInference.ps1 -SkipIntegrationTest
```

### Manual Testing

```powershell
# Module unit tests
Import-Module .\Modules\PcaiInference.psm1 -Force
Test-PcaiInference -Verbose

# Integration test
.\PC-AI.ps1 status -UseNativeInference -Verbose
```

## Troubleshooting

### DLL Not Found

**Symptom:** `WARNING: pcai_inference.dll not found`

**Solution:**
```bash
cd Deploy/pcai-inference
cargo build --features ffi,mistralrs-backend --release
```

**Verify:**
```powershell
Test-Path "Deploy\pcai-inference\target\release\pcai_inference.dll"
```

### Backend Initialization Failed

**Symptom:** `Failed to initialize backend 'mistralrs'`

**Possible Causes:**
- CUDA not available (use `llamacpp` instead)
- Missing Visual C++ redistributables
- Incompatible Rust version during build

**Debug:**
```powershell
Import-Module .\Modules\PcaiInference.psm1
Initialize-PcaiInference -Backend mistralrs -Verbose -ErrorAction Continue
# Check verbose output for specific error
```

### Model Load Failed

**Symptom:** `Failed to load model: <error>`

**Checklist:**
- Model file exists and is readable
- Model format is GGUF or SafeTensors
- Sufficient RAM/VRAM available
- Model compatible with backend (mistralrs supports most GGUF formats)

**Verify:**
```powershell
Get-Item "C:\path\to\model.gguf"
# Should show file size and attributes
```

### Memory Issues

**Symptom:** System slowdown, OOM errors

**Solutions:**
- Reduce `-GpuLayers` to fit VRAM
- Use smaller quantized model (Q4_K_M instead of Q8_0)
- Close other GPU applications
- Increase system page file

## Limitations

1. **Global State:** Only one backend/model active at a time
2. **Streaming:** Only supported for llamacpp backend (not mistralrs)
3. **Model Switching:** Requires `Close-PcaiInference` + reinit to change backends
4. **Windows-Only:** FFI DLL compiled for Windows x64 only

## Future Enhancements

- [ ] Multi-backend support (concurrent backends)
- [ ] Structured error codes (not just strings)
- [ ] Progress callbacks for model loading
- [ ] Streaming support for mistralrs backend
- [ ] Model metadata queries (vocab size, context length)
- [ ] Linux/macOS .so builds
- [ ] Batch inference API

## References

- **FFI Documentation:** Deploy/pcai-inference/FFI_IMPLEMENTATION.md
- **PowerShell Example:** Deploy/pcai-inference/examples/powershell_ffi.ps1
- **Rust Source:** Deploy/pcai-inference/src/ffi.rs
- **mistral.rs:** https://github.com/EricLBuehler/mistral.rs
- **llama.cpp:** https://github.com/ggerganov/llama.cpp

## Support

For issues with:
- **FFI integration:** Check Deploy/pcai-inference/FFI_IMPLEMENTATION.md
- **PowerShell errors:** Run with `-Verbose` flag
- **Build failures:** Ensure Rust 1.75+ and MSVC toolchain installed
- **Model compatibility:** Verify GGUF format with llama.cpp tools
