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
uv run python prepare_dataset.py --output data\functiongemma_train.jsonl
```

## Generate training data (tool schema coverage)

```powershell
uv run python generate_training_data.py ^
  --tools C:\Users\david\PC_AI\Config\pcai-tools.json ^
  --output data\functiongemma_tool_train.jsonl ^
  --test-vectors Reports\TOOL_TEST_VECTORS.json
```

## Train (LoRA)

```powershell
uv run python train_functiongemma.py ^
  --model google/functiongemma-270m-it ^
  --train data\functiongemma_train.jsonl ^
  --output output\functiongemma-lora
```

## Eval harness (tool calling)

```powershell
uv run python eval_harness.py --prompt "Run a WSL network diagnosis and summarize any failures."
```

## Tool router (local HTTP interface)

```powershell
uv run python tool_router.py --port 18010
```

## Tests

```powershell
# Run unit tests only
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\Users\david\PC_AI\Tools\run-functiongemma-tests.ps1 -Category unit

# Run integration tests (vLLM/Docker must be running)
PowerShell -NoProfile -ExecutionPolicy Bypass -File C:\Users\david\PC_AI\Tools\run-functiongemma-tests.ps1 -Category integration
```

## Notes

- The dataset is JSONL with one example per line.
- Each example is rendered into a prompt + tool call format the model expects.
- Ensure examples include a `tools` array (empty list is OK) to avoid chat template errors.
- Adjust batch sizes and max lengths for your GPU.
