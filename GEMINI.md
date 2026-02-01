# GEMINI.md

This repo supports local LLM routing and diagnostics. When interacting with the project:

- Use `DIAGNOSE.md` + `DIAGNOSE_LOGIC.md` for diagnostic output generation.
- Use `CHAT.md` for general assistance.
- Prefer the FunctionGemma runtime for tool selection (`Invoke-LLMChatRouted`).

Tool schema and routing:
- `Config/pcai-tools.json` defines tool names and PowerShell mappings.
- Training and evaluation scripts live under `Deploy/rust-functiongemma-train/` (legacy Python in `Deploy/functiongemma-finetune/`, archived).
- HVSocket endpoints can be referenced via `hvsock://pcai-inference` and `hvsock://functiongemma`.
