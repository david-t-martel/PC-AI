<#
.SYNOPSIS
    Runs the FunctionGemma fine-tuning job in a Docker container with optimized settings.

.DESCRIPTION
    This script encapsulates the complex docker run command required for Unsloth training on Windows/WSL2.
    It handles GPU configuration, memory allocator settings, and volume mounting.

.PARAMETER Build
    If set, rebuilds the Docker image before running.

.PARAMETER Model
    The model ID to fine-tune. Default: unsloth/gemma-2-2b-it-bnb-4bit

.PARAMETER OutputDir
    The output directory for the trained model. Default: out_model

.EXAMPLE
    .\run_training_docker.ps1 -Build
    .\run_training_docker.ps1 -Model "unsloth/gemma-2-9b-it-bnb-4bit"
#>

param(
	[Switch]$Build,
	[String]$Model = 'unsloth/gemma-2-2b-it-bnb-4bit',
	[String]$TrainData = 'train_data.jsonl',
	[String]$OutputDir = 'out_model',
	[String]$ContainerName = 'functiongemma-ft'
)

$ErrorActionPreference = 'Stop'

if ($Build) {
	Write-Host "Building Docker image '$ContainerName'..." -ForegroundColor Cyan
	docker build -t $ContainerName .
	if ($LASTEXITCODE -ne 0) {
		Write-Error 'Docker build failed.'
	}
}

# Ensure training data exists
if (-not (Test-Path $TrainData)) {
	Write-Warning "Training data '$TrainData' not found. Generating dummy data for testing..."
	python generate_training_data.py --tools dummy_tools.json --output $TrainData --test-vectors test_vectors.json --max-cases 10
}

Write-Host 'Starting training run...' -ForegroundColor Green
Write-Host "Model: $Model"
Write-Host "Output: $OutputDir"

# Docker Run Command Explanation:
# --gpus all: expose GPUs
# --entrypoint python: Override Unsloth image's default service entrypoint
# PYTORCH_CUDA_ALLOC_CONF: Fixes CUDA OOM fragmentation
# CUDA_VISIBLE_DEVICES: Isolates to GPU 0 (adjust as needed)
# WANDB_MODE: Disabled by default to avoid login prompts
docker run --rm --gpus all `
	--entrypoint python `
	--env PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True `
	--env CUDA_DEVICE_ORDER=PCI_BUS_ID `
	--env CUDA_VISIBLE_DEVICES=1 `
	--env WANDB_MODE=disabled `
	-v "${PWD}:/workspace" `
	$ContainerName `
	train_functiongemma.py `
	--model $Model `
	--train $TrainData `
	--output $OutputDir `
	--batch-size 2 `
	--epochs 1 `
	--max-seq-len 4096

if ($LASTEXITCODE -eq 0) {
	Write-Host "Training complete. Model saved to $OutputDir" -ForegroundColor Green
} else {
	Write-Error "Training failed with exit code $LASTEXITCODE"
}
