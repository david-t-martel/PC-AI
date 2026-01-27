# GEMINI.md

This repo supports local LLM routing and diagnostics. When interacting with the project:

- Use `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md` for diagnostic output generation.
- Use `CHAT.md` for general assistance.
- Prefer the FunctionGemma router for tool selection (`Invoke-LLMChatRouted`).

Tool schema and routing:
- `Config/pcai-tools.json` defines tool names and PowerShell mappings.
- Training and evaluation scripts live under `Deploy/functiongemma-finetune/`.
- HVSocket endpoints can be referenced via `hvsock://ollama` and `hvsock://vllm`.
