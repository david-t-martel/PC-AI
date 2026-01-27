# vLLM FunctionGemma Stack

This stack runs vLLM's OpenAI-compatible server with FunctionGemma tool calling enabled.

## Usage

```powershell
# From this folder
$env:HF_TOKEN = "<your_hf_token>"
docker compose up -d
```

## Endpoints

- http://127.0.0.1:8000/v1/models
- http://127.0.0.1:8000/v1/chat/completions

## Notes

- Tool calling is enabled via `--enable-auto-tool-choice` and the FunctionGemma tool parser.
- vLLM ships a FunctionGemma chat template at `examples/tool_chat_template_functiongemma.jinja`.
- GPU is enabled via `gpus: all` in Compose.
