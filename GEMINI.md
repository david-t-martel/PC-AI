# GEMINI.md

This repo supports local LLM routing and diagnostics. When interacting with the project:

- Use `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md` for diagnostic output generation.
- Use `CHAT.md` for general assistance.
- Prefer the FunctionGemma runtime for tool selection (`Invoke-LLMChatRouted`).

## Tool schema and routing

- `Config/pcai-tools.json` defines tool names and PowerShell mappings.
- Training and evaluation: `Deploy/rust-functiongemma-train/`
- Router runtime: `Deploy/rust-functiongemma-runtime/`
- HVSocket endpoints: `hvsock://pcai-inference` and `hvsock://functiongemma`

## pcai-inference (Native LLM Engine)

Location: `Native/pcai_core/pcai_inference/`

**Build commands:**
```powershell
# CPU build
.\Invoke-PcaiBuild.ps1 -Backend llamacpp

# CUDA GPU build
.\Invoke-PcaiBuild.ps1 -Backend llamacpp -EnableCuda

# Both backends
.\Invoke-PcaiBuild.ps1 -Backend all -EnableCuda
```

**Backends:**
- `llamacpp`: llama.cpp via llama-cpp-2 (default, GGUF models)
- `mistralrs`: mistral.rs with flash attention (12GB+ VRAM)

**API endpoints:**
- `GET /health` - Health check
- `GET /v1/models` - List loaded models
- `POST /v1/completions` - Generate completion

**Performance config (`Config/llm-config.json`):**
```json
{
  "backend": { "type": "llama_cpp", "n_gpu_layers": 35, "n_ctx": 4096 },
  "model": { "path": "Models/model.gguf" }
}
```

GPU layer offload: 4GB→10-15 layers, 8GB→25-30, 12GB→35-40, 24GB→50+
