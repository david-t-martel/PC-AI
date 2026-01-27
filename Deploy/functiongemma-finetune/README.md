# FunctionGemma Fine-Tuning (Local)

This folder provides a minimal local fine-tuning scaffold for FunctionGemma to improve tool/function calling for PC_AI.

## Setup

```powershell
uv venv .venv
.\.venv\Scripts\activate
uv pip install -r requirements.txt
```

## Prerequisites

- Ensure your Hugging Face account has accepted the Gemma/FunctionGemma license terms.
- Export a `HF_TOKEN` (or `HUGGING_FACE_HUB_TOKEN`) with gated repo access.
- For GPU training, use WSL2 with CUDA-enabled PyTorch.
- Optional for speed: flash-attn (WSL/Linux build recommended).

## Download FunctionGemma model

```powershell
$env:HF_TOKEN = "<your_hf_token_with_gated_repo_access>"
uv run python download_model.py
```

## Prepare data

```powershell
uv run python prepare_dataset.py `
  --output data\functiongemma_train.jsonl `
  --tools C:\Users\david\PC_AI\Config\pcai-tools.json `
  --diagnose-prompt C:\Users\david\PC_AI\DIAGNOSE.md `
  --chat-prompt C:\Users\david\PC_AI\CHAT.md `
  --scenarios C:\Users\david\PC_AI\Deploy\functiongemma-finetune\scenarios.json
```

Notes:
- The dataset now reflects router-only behavior (tool_calls or NO_TOOL).
- Ensure core tools exist in `pcai-tools.json`: SearchDocs, GetSystemInfo, SearchLogs, plus PC_AI module tools.
- Diagnose mode assumes JSON-only output in downstream LLMs; router stays tool-only.

## Generate training data (tool schema coverage)

```powershell
uv run python generate_training_data.py ^
  --tools C:\Users\david\PC_AI\Config\pcai-tools.json ^
  --output data\functiongemma_tool_train.jsonl ^
  --test-vectors Reports\TOOL_TEST_VECTORS.json ^
  --system-prompt C:\Users\david\PC_AI\DIAGNOSE.md ^
  --scenarios C:\Users\david\PC_AI\Deploy\functiongemma-finetune\scenarios.json
```

Notes:
- This creates extra tool coverage examples + test vectors for router quality checks.

## Train (LoRA)

```powershell
uv run python train_functiongemma.py ^
  --model C:\Users\david\PC_AI\Models\functiongemma-270m-it ^
  --train data\functiongemma_train.jsonl ^
  --output output\functiongemma-lora
```

Recommended: log output to a file while training so you can monitor progress:

```powershell
uv run python train_functiongemma.py ^
  --model C:\Users\david\PC_AI\Models\functiongemma-270m-it ^
  --train data\functiongemma_train.jsonl ^
  --output output\functiongemma-lora | Tee-Object -FilePath output\train.log
```

## Eval harness (tool calling)

```powershell
uv run python eval_harness.py `
  --prompt "Run a WSL network diagnosis and summarize any failures." `
  --system-prompt C:\Users\david\PC_AI\DIAGNOSE.md
```

## Periodic checks (router quality)

Use the monitor script to run a subset of scenario prompts on a fixed interval:

```powershell
PowerShell -NoProfile -ExecutionPolicy Bypass -File .\monitor_training.ps1 -Iterations 3 -IntervalSeconds 300
```

This checks that FunctionGemma selects the expected tools or returns NO_TOOL for chat prompts.

## Tool router (local HTTP interface)

```powershell
uv run python tool_router.py --port 18010 --system-prompt C:\Users\david\PC_AI\DIAGNOSE.md
```

## Tests

```powershell
# Run unit tests only
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\Users\david\PC_AI\Tools\run-functiongemma-tests.ps1 -Category unit

# Run integration tests (vLLM/Docker must be running)
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\Users\david\PC_AI\Tools\run-functiongemma-tests.ps1 -Category integration

# Router-specific integration tests (FunctionGemma + provider routing)
pwsh -NoProfile -Command "Invoke-Pester -Path C:\Users\david\PC_AI\Tests\Integration\Router.FunctionGemma.Execution.Tests.ps1,C:\Users\david\PC_AI\Tests\Integration\Router.Providers.Tests.ps1 -Output Detailed"
```

## Notes

- The dataset is JSONL with one example per line.
- Each example is rendered into a prompt + tool call format the model expects.
- Ensure examples include a `tools` array (empty list is OK) to avoid chat template errors.
- Adjust batch sizes and max lengths for your GPU.
- To expand coverage, update `Config/pcai-tools.json` and add new scenarios in `scenarios.json`.
