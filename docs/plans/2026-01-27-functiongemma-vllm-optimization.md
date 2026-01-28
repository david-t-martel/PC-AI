# FunctionGemma & vLLM Multi-GPU Optimization Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Optimize FunctionGemma fine-tuning and vLLM deployment for multi-GPU inference with production-grade reliability.

**Architecture:** Three-phase approach: (1) Training pipeline with QLoRA/validation, (2) Multi-GPU vLLM Docker deployment using RTX 5060 Ti + RTX 2000 Ada, (3) LLM routing with health caching and graceful degradation. All phases use environment variables for path configuration.

**Tech Stack:** Python 3.11+, PyTorch, transformers, peft, trl, vLLM, Docker Compose, PowerShell 7

---

## GPU Configuration

| Index | GPU | VRAM | Assignment |
|-------|-----|------|------------|
| 0 | RTX 2000 Ada | 8 GB | vLLM inference (secondary) |
| 1 | RTX 5060 Ti | 16 GB | vLLM inference (primary), Training |
| - | Intel Arc | 2 GB | System display only |

**vLLM Strategy:** Use `CUDA_VISIBLE_DEVICES=0,1` with tensor parallelism (`--tensor-parallel-size 2`) for ~24GB combined VRAM.

**Training Strategy:** Use GPU 1 (RTX 5060 Ti) exclusively with `CUDA_VISIBLE_DEVICES=1` to avoid contention.

---

## Agent Orchestration Strategy

### Parallel Agent Groups

```
┌─────────────────────────────────────────────────────────────────────┐
│                      PHASE 1: FOUNDATION                             │
│  (All tasks independent - run in parallel)                          │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐                 │
│  │ python-pro  │  │ deployment- │  │ powershell- │                 │
│  │             │  │ engineer    │  │ pro         │                 │
│  │ Task 1:     │  │ Task 2:     │  │ Task 3:     │                 │
│  │ config.py   │  │ .env files  │  │ Resolve-    │                 │
│  │             │  │ docker-     │  │ PcaiPath    │                 │
│  │             │  │ compose     │  │             │                 │
│  └─────────────┘  └─────────────┘  └─────────────┘                 │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│                   PHASE 2: TRAINING & RELIABILITY                    │
│  (Task 4 depends on Task 1; Tasks 5-7 independent)                  │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │
│  │ python-pro  │  │ powershell- │  │ powershell- │  │ powershell│ │
│  │             │  │ pro         │  │ pro         │  │ -pro      │ │
│  │ Task 4:     │  │ Task 5:     │  │ Task 6:     │  │ Task 7:   │ │
│  │ train.py    │  │ Health      │  │ Error       │  │ Graceful  │ │
│  │ enhance     │  │ Cache       │  │ Handling    │  │ Degrade   │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────────┐
│                    PHASE 3: OBSERVABILITY                            │
│  (All tasks depend on Phase 2 completion)                           │
├─────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │
│  │ python-pro  │  │ powershell- │  │ powershell- │  │ test-     │ │
│  │             │  │ pro         │  │ pro         │  │ runner    │ │
│  │ Task 8:     │  │ Task 9:     │  │ Task 10:    │  │ Task 11:  │ │
│  │ Memory      │  │ Tool        │  │ Logging     │  │ E2E       │ │
│  │ Profiler    │  │ Validation  │  │ System      │  │ Tests     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └───────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

### Agent Assignments

| Agent | Tasks | Tools/Plugins | Token Budget |
|-------|-------|---------------|--------------|
| `python-pro` | 1, 4, 8 | context7 (HF docs) | ~15K each |
| `deployment-engineer` | 2 | Docker MCP | ~10K |
| `powershell-pro` | 3, 5, 6, 7, 9, 10 | - | ~8K each |
| `test-runner` | 11 | - | ~12K |
| `code-reviewer` | Post-phase reviews | - | ~5K each |

### MCP Servers & Plugins

| Resource | Usage |
|----------|-------|
| **context7** | Fetch HuggingFace transformers/peft docs for training |
| **Playwright** | E2E testing of vLLM health endpoint |
| **memory** | Store agent handoff context between phases |

### Orchestration Commands

```powershell
# Phase 1: Launch 3 parallel agents
# Use Task tool with 3 concurrent invocations

# Phase 2: Launch 4 parallel agents (after Phase 1 complete)
# python-pro waits for config.py from Phase 1

# Phase 3: Launch 4 parallel agents (after Phase 2 complete)
# All depend on routing infrastructure from Phase 2

# Post-phase: code-reviewer validates each phase
```

---

## PHASE 1: FOUNDATION

### Task 1: Create Environment Configuration (Python)

**Agent:** `python-pro`
**Dependencies:** None
**Parallel Group:** 1A

**Files:**
- Create: `Deploy/functiongemma-finetune/config.py`
- Test: `Deploy/functiongemma-finetune/test_config.py`

**Step 1: Write the failing test**

```python
# Deploy/functiongemma-finetune/test_config.py
import os
import pytest
from pathlib import Path


def test_pcai_root_default():
    """Config should have sensible default for PCAI_ROOT."""
    from config import PcaiConfig
    cfg = PcaiConfig()
    assert cfg.pcai_root.exists() or "PC_AI" in str(cfg.pcai_root)


def test_pcai_root_from_env(monkeypatch):
    """Config should respect PCAI_ROOT environment variable."""
    monkeypatch.setenv("PCAI_ROOT", "/tmp/test_pcai")
    from importlib import reload
    import config
    reload(config)
    cfg = config.PcaiConfig()
    assert str(cfg.pcai_root) == "/tmp/test_pcai"


def test_tools_config_path():
    """Tools config should resolve relative to root."""
    from config import PcaiConfig
    cfg = PcaiConfig()
    assert cfg.tools_config.name == "pcai-tools.json"


def test_model_path():
    """Model path should resolve correctly."""
    from config import PcaiConfig
    cfg = PcaiConfig()
    assert "functiongemma" in str(cfg.model_path).lower()
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pytest test_config.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'config'"

**Step 3: Write minimal implementation**

```python
# Deploy/functiongemma-finetune/config.py
"""Centralized configuration for FunctionGemma training pipeline."""
import os
from pathlib import Path
from dataclasses import dataclass, field
from typing import Optional


def _get_default_root() -> Path:
    """Determine default PCAI_ROOT from environment or common locations."""
    if env_root := os.environ.get("PCAI_ROOT"):
        return Path(env_root)

    # Check common locations
    candidates = [
        Path(__file__).parent.parent.parent,  # Deploy/functiongemma-finetune -> PC_AI
        Path.home() / "PC_AI",
        Path("C:/Users/david/PC_AI"),
    ]
    for candidate in candidates:
        if (candidate / "Config" / "pcai-tools.json").exists():
            return candidate

    return candidates[0]


@dataclass
class PcaiConfig:
    """Configuration container with environment variable support."""

    pcai_root: Path = field(default_factory=_get_default_root)

    def __post_init__(self):
        # Allow string paths
        if isinstance(self.pcai_root, str):
            self.pcai_root = Path(self.pcai_root)

    @property
    def tools_config(self) -> Path:
        """Path to pcai-tools.json."""
        return Path(os.environ.get(
            "PCAI_TOOLS_CONFIG",
            self.pcai_root / "Config" / "pcai-tools.json"
        ))

    @property
    def model_path(self) -> Path:
        """Path to FunctionGemma model directory."""
        return Path(os.environ.get(
            "PCAI_MODEL_PATH",
            self.pcai_root / "Models" / "functiongemma-270m-it"
        ))

    @property
    def output_path(self) -> Path:
        """Default output path for fine-tuned models."""
        return Path(os.environ.get(
            "PCAI_OUTPUT_PATH",
            self.pcai_root / "Models" / "functiongemma-finetuned"
        ))

    @property
    def training_data_path(self) -> Path:
        """Path to training data directory."""
        return self.pcai_root / "Deploy" / "functiongemma-finetune" / "data"

    @property
    def logs_path(self) -> Path:
        """Path to logs directory."""
        return self.pcai_root / "Reports" / "Logs"


# Singleton instance
_config: Optional[PcaiConfig] = None


def get_config() -> PcaiConfig:
    """Get or create the singleton config instance."""
    global _config
    if _config is None:
        _config = PcaiConfig()
    return _config


def reset_config():
    """Reset config (useful for testing)."""
    global _config
    _config = None
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pytest test_config.py -v`
Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add Deploy/functiongemma-finetune/config.py Deploy/functiongemma-finetune/test_config.py
git commit -m "feat(training): add centralized config with env var support"
```

---

### Task 2: Create vLLM Docker Multi-GPU Configuration

**Agent:** `deployment-engineer`
**Dependencies:** None
**Parallel Group:** 1B

**Files:**
- Create: `Deploy/docker/vllm/.env.example`
- Create: `Deploy/docker/vllm/.env` (gitignored)
- Modify: `Deploy/docker/vllm/docker-compose.yml`
- Modify: `.gitignore`

**Step 1: Create .env.example template**

```env
# Deploy/docker/vllm/.env.example
# Copy to .env and customize

# HuggingFace token (required for gated models)
HF_TOKEN=your_hf_token_here

# GPU Configuration
# GPU 0: RTX 2000 Ada (8GB), GPU 1: RTX 5060 Ti (16GB)
CUDA_VISIBLE_DEVICES=0,1

# vLLM Settings
GPU_MEMORY_UTILIZATION=0.85
MAX_MODEL_LEN=4096
TENSOR_PARALLEL_SIZE=2

# Container Resources
CONTAINER_MEMORY_LIMIT=24g
SHM_SIZE=8g

# Logging
VLLM_LOGGING_LEVEL=INFO
```

**Step 2: Create actual .env file**

```env
# Deploy/docker/vllm/.env
HF_TOKEN=${HF_TOKEN}
CUDA_VISIBLE_DEVICES=0,1
GPU_MEMORY_UTILIZATION=0.85
MAX_MODEL_LEN=4096
TENSOR_PARALLEL_SIZE=2
CONTAINER_MEMORY_LIMIT=24g
SHM_SIZE=8g
VLLM_LOGGING_LEVEL=INFO
```

**Step 3: Update docker-compose.yml for multi-GPU**

```yaml
# Deploy/docker/vllm/docker-compose.yml
services:
  vllm-functiongemma:
    image: vllm/vllm-openai:latest
    container_name: vllm-functiongemma
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - HF_TOKEN=${HF_TOKEN}
      - HUGGING_FACE_HUB_TOKEN=${HF_TOKEN}
      - HF_HUB_OFFLINE=1
      - CUDA_DEVICE_ORDER=PCI_BUS_ID
      - CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES:-0,1}
      - VLLM_LOGGING_LEVEL=${VLLM_LOGGING_LEVEL:-INFO}
      - VLLM_ATTENTION_BACKEND=FLASH_ATTN
    volumes:
      - C:\Users\david\.cache\huggingface:/root/.cache/huggingface
      - C:\Users\david\PC_AI\Models\functiongemma-270m-it:/models/functiongemma-270m-it
      - C:\Users\david\PC_AI\Deploy\docker\vllm\tool_chat_template_functiongemma.jinja:/opt/pcai/tool_chat_template_functiongemma.jinja:ro
    deploy:
      resources:
        limits:
          memory: ${CONTAINER_MEMORY_LIMIT:-24g}
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [gpu]
    shm_size: ${SHM_SIZE:-8g}
    ipc: host
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 120s
    command:
      - --model
      - /models/functiongemma-270m-it
      - --served-model-name
      - functiongemma-270m-it
      - --enable-auto-tool-choice
      - --tool-call-parser
      - functiongemma
      - --chat-template
      - /opt/pcai/tool_chat_template_functiongemma.jinja
      - --max-model-len
      - "${MAX_MODEL_LEN:-4096}"
      - --gpu-memory-utilization
      - "${GPU_MEMORY_UTILIZATION:-0.85}"
      - --tensor-parallel-size
      - "${TENSOR_PARALLEL_SIZE:-2}"
      - --max-num-seqs
      - "16"
      - --disable-log-requests
```

**Step 4: Update .gitignore**

Add to `.gitignore`:
```
# vLLM secrets
Deploy/docker/vllm/.env
```

**Step 5: Test Docker configuration**

Run: `cd C:\Users\david\PC_AI\Deploy\docker\vllm && docker compose config`
Expected: Valid YAML output with resolved variables

**Step 6: Commit**

```bash
git add Deploy/docker/vllm/.env.example Deploy/docker/vllm/docker-compose.yml .gitignore
git commit -m "feat(docker): multi-GPU vLLM config with tensor parallelism"
```

---

### Task 3: Create Path Resolution Module (PowerShell)

**Agent:** `powershell-pro` (PowerShell expertise)
**Dependencies:** None
**Parallel Group:** 1C

**Files:**
- Create: `Modules/PC-AI.LLM/Private/Resolve-PcaiPath.ps1`
- Test: `Tests/Unit/Resolve-PcaiPath.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/Resolve-PcaiPath.Tests.ps1
BeforeAll {
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM'
    . (Join-Path $ModuleRoot 'Private\Resolve-PcaiPath.ps1')
}

Describe 'Resolve-PcaiPath' {
    Context 'Default resolution' {
        It 'Should resolve project root from module location' {
            $root = Resolve-PcaiPath -PathType 'Root'
            $root | Should -Match 'PC_AI'
        }

        It 'Should resolve Config path' {
            $config = Resolve-PcaiPath -PathType 'Config'
            Test-Path $config | Should -BeTrue
        }

        It 'Should resolve HVSock config' {
            $hvsock = Resolve-PcaiPath -PathType 'HVSockConfig'
            $hvsock | Should -Match 'hvsock-proxy\.conf'
        }
    }

    Context 'Environment variable override' {
        It 'Should respect PCAI_ROOT environment variable' {
            $env:PCAI_ROOT = 'C:\TestRoot'
            try {
                $root = Resolve-PcaiPath -PathType 'Root'
                $root | Should -Be 'C:\TestRoot'
            } finally {
                Remove-Item Env:\PCAI_ROOT -ErrorAction SilentlyContinue
            }
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Resolve-PcaiPath.Tests.ps1 -Output Detailed`
Expected: FAIL with "Resolve-PcaiPath is not recognized"

**Step 3: Write minimal implementation**

```powershell
# Modules/PC-AI.LLM/Private/Resolve-PcaiPath.ps1
#Requires -Version 5.1

<#
.SYNOPSIS
    Resolves PC_AI paths dynamically with environment variable support.

.PARAMETER PathType
    The type of path to resolve: Root, Config, HVSockConfig, Models, Logs

.OUTPUTS
    String path to the requested resource
#>
function Resolve-PcaiPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Root', 'Config', 'HVSockConfig', 'Models', 'Logs', 'Tools')]
        [string]$PathType
    )

    # Determine root path
    $root = $null

    # 1. Check environment variable
    if ($env:PCAI_ROOT) {
        $root = $env:PCAI_ROOT
    }
    # 2. Derive from module location
    elseif ($PSScriptRoot) {
        # Private -> PC-AI.LLM -> Modules -> PC_AI
        $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    }
    # 3. Fallback to known location
    else {
        $root = 'C:\Users\david\PC_AI'
    }

    switch ($PathType) {
        'Root' { return $root }
        'Config' { return Join-Path $root 'Config' }
        'HVSockConfig' { return Join-Path $root 'Config\hvsock-proxy.conf' }
        'Models' { return Join-Path $root 'Models' }
        'Logs' { return Join-Path $root 'Reports\Logs' }
        'Tools' { return Join-Path $root 'Config\pcai-tools.json' }
        default { return $root }
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Resolve-PcaiPath.Tests.ps1 -Output Detailed`
Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Private/Resolve-PcaiPath.ps1 Tests/Unit/Resolve-PcaiPath.Tests.ps1
git commit -m "feat(llm): add dynamic path resolution with env var support"
```

---

## PHASE 2: TRAINING & RELIABILITY

### Task 4: Enhance Training Script with LR Scheduling & QLoRA

**Agent:** `python-pro`
**Dependencies:** Task 1 (config.py)
**Parallel Group:** 2A

**Files:**
- Modify: `Deploy/functiongemma-finetune/train_functiongemma.py`
- Test: `Deploy/functiongemma-finetune/test_train.py`

**Step 1: Write the failing test**

```python
# Deploy/functiongemma-finetune/test_train.py
import pytest
from train_functiongemma import TrainConfigModel, parse_args
import sys


def test_lr_scheduler_default():
    """Config should have cosine LR scheduler by default."""
    sys.argv = ['train', '--model', 'test', '--train', 'test.json', '--output', 'out']
    cfg = parse_args()
    assert cfg.lr_scheduler_type == 'cosine'


def test_warmup_ratio_default():
    """Config should have 10% warmup by default."""
    sys.argv = ['train', '--model', 'test', '--train', 'test.json', '--output', 'out']
    cfg = parse_args()
    assert cfg.warmup_ratio == 0.1


def test_eval_split_configurable():
    """Eval split should be configurable via CLI."""
    sys.argv = ['train', '--model', 'test', '--train', 'test.json', '--output', 'out', '--eval-split', '0.15']
    cfg = parse_args()
    assert cfg.eval_split == 0.15


def test_use_4bit_flag():
    """QLoRA 4-bit should be opt-in."""
    sys.argv = ['train', '--model', 'test', '--train', 'test.json', '--output', 'out', '--use-4bit']
    cfg = parse_args()
    assert cfg.use_4bit is True


def test_resume_checkpoint():
    """Resume from checkpoint should work."""
    sys.argv = ['train', '--model', 'test', '--train', 'test.json', '--output', 'out', '--resume-from-checkpoint', 'latest']
    cfg = parse_args()
    assert cfg.resume_from_checkpoint == 'latest'
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pytest test_train.py -v`
Expected: FAIL with "AttributeError: 'TrainConfigModel' has no attribute 'lr_scheduler_type'"

**Step 3: Update TrainConfigModel and parse_args**

Update `train_functiongemma.py`:

```python
# Add to TrainConfigModel class (after line 41)
    lr_scheduler_type: str = Field(default="cosine", description="LR scheduler: linear|cosine|constant")
    warmup_ratio: float = Field(default=0.1, description="Warmup ratio (0.0-1.0)")
    eval_split: float = Field(default=0.0, description="Validation split ratio (0.0-0.3)")
    early_stopping_patience: int = Field(default=3, description="Early stopping patience epochs")
    use_4bit: bool = Field(default=False, description="Use QLoRA 4-bit quantization")
    resume_from_checkpoint: Optional[str] = Field(default=None, description="Checkpoint path or 'latest'")

# Add to parse_args function (after line 58)
    parser.add_argument("--lr-scheduler", dest="lr_scheduler_type", default="cosine", choices=["linear", "cosine", "constant"])
    parser.add_argument("--warmup-ratio", type=float, default=0.1)
    parser.add_argument("--eval-split", type=float, default=0.0)
    parser.add_argument("--early-stopping-patience", type=int, default=3)
    parser.add_argument("--use-4bit", action="store_true")
    parser.add_argument("--resume-from-checkpoint", default=None)

# Add to TrainConfigModel construction in parse_args (after line 76)
            lr_scheduler_type=args.lr_scheduler_type,
            warmup_ratio=args.warmup_ratio,
            eval_split=args.eval_split,
            early_stopping_patience=args.early_stopping_patience,
            use_4bit=args.use_4bit,
            resume_from_checkpoint=args.resume_from_checkpoint,
```

**Step 4: Update main() to use new config**

```python
# In main(), after model loading (around line 109), add QLoRA support:
    if args.use_4bit:
        from transformers import BitsAndBytesConfig
        bnb_config = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch_dtype,
            bnb_4bit_use_double_quant=True,
        )
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            device_map="auto",
            torch_dtype=torch_dtype,
            quantization_config=bnb_config,
        )
    else:
        model = AutoModelForCausalLM.from_pretrained(
            args.model,
            device_map="auto",
            torch_dtype=torch_dtype,
        )

# Add validation split (after dataset loading, around line 126):
    if args.eval_split > 0:
        split = dataset.train_test_split(test_size=args.eval_split, seed=args.seed)
        train_dataset = split["train"]
        eval_dataset = split["test"]
    else:
        train_dataset = dataset
        eval_dataset = None

# Update SFTConfig (around line 136):
    cfg_kwargs = {
        "output_dir": args.output,
        "per_device_train_batch_size": args.batch_size,
        "gradient_accumulation_steps": args.grad_accum,
        "num_train_epochs": args.epochs,
        "learning_rate": args.lr,
        "lr_scheduler_type": args.lr_scheduler_type,
        "warmup_ratio": args.warmup_ratio,
        "logging_steps": 10,
        "save_steps": 200,
        "save_total_limit": 2,
        "bf16": torch_dtype == torch.bfloat16,
        "fp16": torch_dtype == torch.float16,
        "packing": args.packing,
        "evaluation_strategy": "steps" if eval_dataset else "no",
        "eval_steps": 100 if eval_dataset else None,
        "load_best_model_at_end": True if eval_dataset else False,
    }

# Update trainer construction:
    trainer_kwargs = {
        "model": model,
        "train_dataset": train_dataset,
        "eval_dataset": eval_dataset,
        "peft_config": lora,
        "args": cfg,
    }

# Add checkpoint resume (before trainer.train()):
    resume_ckpt = None
    if args.resume_from_checkpoint:
        if args.resume_from_checkpoint == "latest":
            import glob
            checkpoints = glob.glob(f"{args.output}/checkpoint-*")
            if checkpoints:
                resume_ckpt = max(checkpoints, key=os.path.getctime)
        else:
            resume_ckpt = args.resume_from_checkpoint

    trainer.train(resume_from_checkpoint=resume_ckpt)
```

**Step 5: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pytest test_train.py -v`
Expected: PASS (5 tests)

**Step 6: Commit**

```bash
git add Deploy/functiongemma-finetune/train_functiongemma.py Deploy/functiongemma-finetune/test_train.py
git commit -m "feat(training): add LR scheduling, QLoRA, validation split, checkpoint resume"
```

---

### Task 5: Create Provider Health Cache

**Agent:** `powershell-pro`
**Dependencies:** Task 3 (Resolve-PcaiPath.ps1)
**Parallel Group:** 2B

**Files:**
- Create: `Modules/PC-AI.LLM/Private/ProviderHealthCache.ps1`
- Test: `Tests/Unit/ProviderHealthCache.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/ProviderHealthCache.Tests.ps1
BeforeAll {
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM'
    . (Join-Path $ModuleRoot 'Private\ProviderHealthCache.ps1')
}

Describe 'ProviderHealthCache' {
    BeforeEach {
        Reset-ProviderHealthCache
    }

    Context 'Cache operations' {
        It 'Should cache health check results' {
            Set-ProviderHealthCache -Provider 'ollama' -IsHealthy $true
            $result = Get-ProviderHealthCache -Provider 'ollama'
            $result.IsHealthy | Should -BeTrue
        }

        It 'Should return null for uncached providers' {
            $result = Get-ProviderHealthCache -Provider 'unknown'
            $result | Should -BeNull
        }

        It 'Should expire cache after TTL' {
            Set-ProviderHealthCache -Provider 'vllm' -IsHealthy $true
            # Simulate time passing by manipulating the cache
            $script:ProviderHealthCache.Results['vllm'].CachedAt = (Get-Date).AddSeconds(-60)
            $result = Get-ProviderHealthCache -Provider 'vllm'
            $result | Should -BeNull
        }
    }

    Context 'Get-CachedProviderHealth integration' {
        It 'Should use cache for repeated checks' {
            # Mock the actual health check
            Mock Test-OllamaConnection { $true } -ModuleName PC-AI.LLM

            $first = Get-CachedProviderHealth -Provider 'ollama'
            $second = Get-CachedProviderHealth -Provider 'ollama'

            # Should only call actual check once due to caching
            Should -Invoke Test-OllamaConnection -Times 1
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\ProviderHealthCache.Tests.ps1 -Output Detailed`
Expected: FAIL with "Reset-ProviderHealthCache is not recognized"

**Step 3: Write minimal implementation**

```powershell
# Modules/PC-AI.LLM/Private/ProviderHealthCache.ps1
#Requires -Version 5.1

<#
.SYNOPSIS
    Provider health check caching to reduce latency on repeated LLM calls.
#>

# Module-scoped cache
$script:ProviderHealthCache = @{
    Results = @{}
    CacheTTLSeconds = 30
}

function Reset-ProviderHealthCache {
    <#
    .SYNOPSIS
        Clears all cached health check results.
    #>
    [CmdletBinding()]
    param()

    $script:ProviderHealthCache.Results = @{}
    Write-Verbose "Provider health cache cleared"
}

function Set-ProviderHealthCache {
    <#
    .SYNOPSIS
        Stores a provider health check result in cache.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ollama', 'vllm', 'lmstudio')]
        [string]$Provider,

        [Parameter(Mandatory)]
        [bool]$IsHealthy,

        [Parameter()]
        [string]$Message
    )

    $script:ProviderHealthCache.Results[$Provider] = @{
        IsHealthy = $IsHealthy
        Message = $Message
        CachedAt = Get-Date
    }
    Write-Verbose "Cached health for $Provider`: $IsHealthy"
}

function Get-ProviderHealthCache {
    <#
    .SYNOPSIS
        Retrieves cached health check result if not expired.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Provider
    )

    if (-not $script:ProviderHealthCache.Results.ContainsKey($Provider)) {
        return $null
    }

    $cached = $script:ProviderHealthCache.Results[$Provider]
    $age = (Get-Date) - $cached.CachedAt

    if ($age.TotalSeconds -gt $script:ProviderHealthCache.CacheTTLSeconds) {
        Write-Verbose "Cache expired for $Provider (age: $($age.TotalSeconds)s)"
        $script:ProviderHealthCache.Results.Remove($Provider)
        return $null
    }

    Write-Verbose "Cache hit for $Provider (age: $($age.TotalSeconds)s)"
    return [PSCustomObject]@{
        Provider = $Provider
        IsHealthy = $cached.IsHealthy
        Message = $cached.Message
        CachedAt = $cached.CachedAt
        AgeSeconds = [int]$age.TotalSeconds
    }
}

function Get-CachedProviderHealth {
    <#
    .SYNOPSIS
        Gets provider health using cache, falling back to actual check.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('ollama', 'vllm', 'lmstudio')]
        [string]$Provider,

        [Parameter()]
        [int]$TimeoutSeconds = 5
    )

    # Check cache first
    $cached = Get-ProviderHealthCache -Provider $Provider
    if ($null -ne $cached) {
        Write-Verbose "Using cached health for $Provider"
        return $cached.IsHealthy
    }

    # Perform actual health check
    $isHealthy = $false
    $message = ''

    try {
        switch ($Provider) {
            'ollama' {
                $isHealthy = Test-OllamaConnection -TimeoutSeconds $TimeoutSeconds
                $message = if ($isHealthy) { 'Connected' } else { 'Connection failed' }
            }
            'vllm' {
                $isHealthy = Test-OpenAIConnection -ApiUrl $script:ModuleConfig.VLLMApiUrl -TimeoutSeconds $TimeoutSeconds
                $message = if ($isHealthy) { 'Connected' } else { 'Connection failed' }
            }
            'lmstudio' {
                $isHealthy = Test-OpenAIConnection -ApiUrl $script:ModuleConfig.LMStudioApiUrl -TimeoutSeconds $TimeoutSeconds
                $message = if ($isHealthy) { 'Connected' } else { 'Connection failed' }
            }
        }
    } catch {
        $message = $_.Exception.Message
    }

    # Cache result
    Set-ProviderHealthCache -Provider $Provider -IsHealthy $isHealthy -Message $message

    return $isHealthy
}

function Set-ProviderHealthCacheTTL {
    <#
    .SYNOPSIS
        Configures the cache TTL in seconds.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(5, 300)]
        [int]$Seconds
    )

    $script:ProviderHealthCache.CacheTTLSeconds = $Seconds
    Write-Verbose "Cache TTL set to $Seconds seconds"
}
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\ProviderHealthCache.Tests.ps1 -Output Detailed`
Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Private/ProviderHealthCache.ps1 Tests/Unit/ProviderHealthCache.Tests.ps1
git commit -m "feat(llm): add provider health caching with 30s TTL"
```

---

### Task 6: Create Error Handling & Retry Module

**Agent:** `powershell-pro`
**Dependencies:** Task 5 (ProviderHealthCache)
**Parallel Group:** 2C

**Files:**
- Create: `Modules/PC-AI.LLM/Private/LLM-ErrorHandling.ps1`
- Test: `Tests/Unit/LLM-ErrorHandling.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/LLM-ErrorHandling.Tests.ps1
BeforeAll {
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM'
    . (Join-Path $ModuleRoot 'Private\LLM-ErrorHandling.ps1')
}

Describe 'LLM-ErrorHandling' {
    Context 'Error classification' {
        It 'Should classify connection errors' {
            $error = [System.Net.WebException]::new("Connection refused")
            $category = Get-LLMErrorCategory -Exception $error
            $category | Should -Be 'Connectivity'
        }

        It 'Should classify timeout errors' {
            $error = [System.TimeoutException]::new("Request timeout")
            $category = Get-LLMErrorCategory -Exception $error
            $category | Should -Be 'Timeout'
        }
    }

    Context 'Retry logic' {
        It 'Should retry on transient errors' {
            $attempts = 0
            $result = Invoke-WithRetry -ScriptBlock {
                $script:attempts++
                if ($script:attempts -lt 3) { throw [System.Net.WebException]::new("Retry me") }
                return "success"
            } -MaxRetries 3

            $result | Should -Be "success"
            $attempts | Should -Be 3
        }

        It 'Should not retry on non-transient errors' {
            $attempts = 0
            {
                Invoke-WithRetry -ScriptBlock {
                    $script:attempts++
                    throw [System.ArgumentException]::new("Bad input")
                } -MaxRetries 3
            } | Should -Throw

            $attempts | Should -Be 1
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\LLM-ErrorHandling.Tests.ps1 -Output Detailed`
Expected: FAIL with "Get-LLMErrorCategory is not recognized"

**Step 3: Write minimal implementation**

```powershell
# Modules/PC-AI.LLM/Private/LLM-ErrorHandling.ps1
#Requires -Version 5.1

<#
.SYNOPSIS
    LLM error handling with categorization and retry logic.
#>

enum LLMErrorCategory {
    Connectivity
    Timeout
    RateLimited
    ServerError
    ClientError
    Unknown
}

function Get-LLMErrorCategory {
    <#
    .SYNOPSIS
        Classifies an exception into an LLM error category.
    #>
    [CmdletBinding()]
    [OutputType([LLMErrorCategory])]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception
    )

    $message = $Exception.Message.ToLower()
    $type = $Exception.GetType().Name

    # Connection errors
    if ($type -eq 'WebException' -or $message -match 'connection|refused|unreachable|network') {
        return [LLMErrorCategory]::Connectivity
    }

    # Timeout errors
    if ($type -eq 'TimeoutException' -or $message -match 'timeout|timed out') {
        return [LLMErrorCategory]::Timeout
    }

    # Rate limiting
    if ($message -match 'rate limit|429|too many requests') {
        return [LLMErrorCategory]::RateLimited
    }

    # Server errors (5xx)
    if ($message -match '50[0-9]|server error|internal error') {
        return [LLMErrorCategory]::ServerError
    }

    # Client errors (4xx except 429)
    if ($message -match '4[0-8][0-9]|bad request|unauthorized|forbidden|not found') {
        return [LLMErrorCategory]::ClientError
    }

    return [LLMErrorCategory]::Unknown
}

function Test-IsTransientError {
    <#
    .SYNOPSIS
        Determines if an error is transient and worth retrying.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [LLMErrorCategory]$Category
    )

    return $Category -in @(
        [LLMErrorCategory]::Connectivity,
        [LLMErrorCategory]::Timeout,
        [LLMErrorCategory]::RateLimited,
        [LLMErrorCategory]::ServerError
    )
}

function Invoke-WithRetry {
    <#
    .SYNOPSIS
        Executes a script block with exponential backoff retry on transient errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$ScriptBlock,

        [Parameter()]
        [ValidateRange(1, 5)]
        [int]$MaxRetries = 3,

        [Parameter()]
        [ValidateRange(0.5, 10)]
        [double]$BaseDelaySeconds = 1.0,

        [Parameter()]
        [switch]$RetryAllErrors
    )

    $attempt = 0
    $lastException = $null

    while ($attempt -lt $MaxRetries) {
        $attempt++

        try {
            return & $ScriptBlock
        }
        catch {
            $lastException = $_.Exception
            $category = Get-LLMErrorCategory -Exception $lastException

            Write-Verbose "Attempt $attempt failed: [$category] $($lastException.Message)"

            # Check if error is retryable
            $shouldRetry = $RetryAllErrors -or (Test-IsTransientError -Category $category)

            if (-not $shouldRetry) {
                Write-Verbose "Non-transient error, not retrying"
                throw
            }

            if ($attempt -lt $MaxRetries) {
                # Exponential backoff: 1s, 2s, 4s
                $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt - 1)
                Write-Verbose "Retrying in $delay seconds..."
                Start-Sleep -Seconds $delay
            }
        }
    }

    # All retries exhausted
    throw $lastException
}

function New-LLMErrorReport {
    <#
    .SYNOPSIS
        Creates a structured error report for logging.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [System.Exception]$Exception,

        [Parameter()]
        [string]$Provider,

        [Parameter()]
        [string]$Operation,

        [Parameter()]
        [int]$AttemptCount = 1
    )

    $category = Get-LLMErrorCategory -Exception $Exception

    return [PSCustomObject]@{
        Timestamp = Get-Date -Format 'o'
        Provider = $Provider
        Operation = $Operation
        Category = $category.ToString()
        IsTransient = Test-IsTransientError -Category $category
        Message = $Exception.Message
        ExceptionType = $Exception.GetType().FullName
        AttemptCount = $AttemptCount
        StackTrace = $Exception.StackTrace
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\LLM-ErrorHandling.Tests.ps1 -Output Detailed`
Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Private/LLM-ErrorHandling.ps1 Tests/Unit/LLM-ErrorHandling.Tests.ps1
git commit -m "feat(llm): add error categorization and exponential backoff retry"
```

---

### Task 7: Add Graceful Degradation to Router

**Agent:** `powershell-pro`
**Dependencies:** Tasks 5, 6 (Health cache, Error handling)
**Parallel Group:** 2D

**Files:**
- Modify: `Modules/PC-AI.LLM/Public/Invoke-LLMChatRouted.ps1`
- Test: `Tests/Unit/Invoke-LLMChatRouted.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/Invoke-LLMChatRouted.Tests.ps1 (add to existing)
Describe 'Invoke-LLMChatRouted Graceful Degradation' {
    Context 'BypassRouter parameter' {
        It 'Should have BypassRouter parameter' {
            $cmd = Get-Command Invoke-LLMChatRouted
            $cmd.Parameters.ContainsKey('BypassRouter') | Should -BeTrue
        }

        It 'Should skip router when BypassRouter is set' {
            Mock Invoke-FunctionGemmaReAct { throw "Should not be called" }
            Mock Invoke-LLMChatWithFallback {
                [PSCustomObject]@{ message = @{ content = "Direct response" }; Provider = 'ollama' }
            }

            $result = Invoke-LLMChatRouted -Message "Test" -BypassRouter
            $result.DegradedMode | Should -BeTrue
            $result.RouterAvailable | Should -BeFalse
        }
    }

    Context 'Automatic fallback' {
        It 'Should fall back when router is unavailable' {
            Mock Invoke-FunctionGemmaReAct { throw "Router unavailable" }
            Mock Invoke-LLMChatWithFallback {
                [PSCustomObject]@{ message = @{ content = "Fallback response" }; Provider = 'ollama' }
            }

            $result = Invoke-LLMChatRouted -Message "Test"
            $result.DegradedMode | Should -BeTrue
            $result.RouterError | Should -Match "Router unavailable"
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Invoke-LLMChatRouted.Tests.ps1 -Output Detailed`
Expected: FAIL with "BypassRouter parameter not found" or similar

**Step 3: Update Invoke-LLMChatRouted.ps1**

Add after line 87 (before `$EnforceJson`):

```powershell
        [Parameter()]
        [switch]$BypassRouter
```

Replace the router invocation section (around lines 107-115):

```powershell
    $routerResult = $null
    $routerError = $null
    $degradedMode = $false

    if (-not $BypassRouter) {
        # Check router health first
        $routerHealthy = Get-CachedProviderHealth -Provider 'vllm' -TimeoutSeconds 3

        if ($routerHealthy) {
            try {
                $routerResult = Invoke-WithRetry -ScriptBlock {
                    Invoke-FunctionGemmaReAct `
                        -Prompt $routerPrompt `
                        -BaseUrl $RouterBaseUrl `
                        -Model $RouterModel `
                        -ToolsPath $ToolsPath `
                        -ExecuteTools:$ExecuteTools `
                        -ReturnFinal:$false `
                        -MaxToolCalls $MaxToolCalls `
                        -TimeoutSeconds $TimeoutSeconds
                } -MaxRetries 2
            }
            catch {
                $routerError = $_.Exception.Message
                Write-Warning "Router failed, degrading to direct LLM: $routerError"
                $degradedMode = $true
            }
        }
        else {
            $routerError = "Router health check failed"
            Write-Warning "Router unavailable, using direct LLM"
            $degradedMode = $true
        }
    }
    else {
        $degradedMode = $true
        $routerError = "Bypassed by user request"
        Write-Verbose "Router bypassed by BypassRouter parameter"
    }

    $toolResults = if ($routerResult) { $routerResult.ToolResults } else { @() }
    $toolCalls = if ($routerResult) { $routerResult.ToolCalls } else { @() }
```

Update the return object (around line 157):

```powershell
    return [PSCustomObject]@{
        Mode = $Mode
        Prompt = $Message
        ToolCalls = $toolCalls
        ToolResults = $toolResults
        Response = $finalResponse.message.content
        ResponseJson = $responseJson
        JsonValid = $jsonValid
        JsonError = $jsonError
        Provider = $finalResponse.Provider
        Model = $Model
        RouterModel = $RouterModel
        RouterBaseUrl = $RouterBaseUrl
        RouterAvailable = (-not $degradedMode -or $routerResult)
        DegradedMode = $degradedMode
        RouterError = $routerError
        Timestamp = Get-Date
    }
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Invoke-LLMChatRouted.Tests.ps1 -Output Detailed`
Expected: PASS

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Public/Invoke-LLMChatRouted.ps1 Tests/Unit/Invoke-LLMChatRouted.Tests.ps1
git commit -m "feat(llm): add graceful degradation with BypassRouter and auto-fallback"
```

---

## PHASE 3: OBSERVABILITY

### Task 8: Create Memory Profiler for Training

**Agent:** `python-pro`
**Dependencies:** Task 1 (config.py)
**Parallel Group:** 3A

**Files:**
- Create: `Deploy/functiongemma-finetune/memory_profiler.py`
- Test: `Deploy/functiongemma-finetune/test_memory_profiler.py`
- Modify: `Deploy/functiongemma-finetune/requirements.txt`

**Step 1: Add psutil to requirements.txt**

Add to `requirements.txt`:
```
psutil>=5.9.0
```

**Step 2: Write the failing test**

```python
# Deploy/functiongemma-finetune/test_memory_profiler.py
import pytest


def test_get_memory_snapshot():
    """Should return memory snapshot with required fields."""
    from memory_profiler import get_memory_snapshot

    snapshot = get_memory_snapshot()

    assert 'cpu_percent' in snapshot
    assert 'ram_used_gb' in snapshot
    assert 'ram_total_gb' in snapshot
    assert 'swap_used_gb' in snapshot
    assert 'swap_percent' in snapshot


def test_estimate_training_memory():
    """Should estimate memory requirements for training."""
    from memory_profiler import estimate_training_memory

    estimate = estimate_training_memory(
        model_params_millions=270,
        batch_size=1,
        seq_length=4096,
        use_4bit=False
    )

    assert 'model_memory_gb' in estimate
    assert 'activation_memory_gb' in estimate
    assert 'total_estimated_gb' in estimate
    assert estimate['total_estimated_gb'] > 0


def test_check_memory_feasibility():
    """Should warn if estimated memory exceeds available."""
    from memory_profiler import check_memory_feasibility

    result = check_memory_feasibility(required_gb=1000)  # Unreasonably high

    assert result['feasible'] is False
    assert 'warning' in result


def test_swap_warning():
    """Should warn if swap usage is high."""
    from memory_profiler import get_memory_snapshot

    snapshot = get_memory_snapshot()
    # Just verify the field exists and is a number
    assert isinstance(snapshot['swap_percent'], (int, float))
```

**Step 3: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pytest test_memory_profiler.py -v`
Expected: FAIL with "ModuleNotFoundError: No module named 'memory_profiler'"

**Step 4: Write minimal implementation**

```python
# Deploy/functiongemma-finetune/memory_profiler.py
"""Memory profiling utilities for FunctionGemma training."""
import os
from typing import Dict, Any, Optional

try:
    import psutil
    PSUTIL_AVAILABLE = True
except ImportError:
    PSUTIL_AVAILABLE = False

try:
    import torch
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


def get_memory_snapshot() -> Dict[str, Any]:
    """
    Get current memory usage snapshot.

    Returns:
        Dict with cpu_percent, ram_used_gb, ram_total_gb, swap_used_gb, swap_percent,
        and optionally gpu_used_gb, gpu_total_gb.
    """
    snapshot = {
        'cpu_percent': 0.0,
        'ram_used_gb': 0.0,
        'ram_total_gb': 0.0,
        'swap_used_gb': 0.0,
        'swap_percent': 0.0,
    }

    if PSUTIL_AVAILABLE:
        snapshot['cpu_percent'] = psutil.cpu_percent(interval=0.1)

        mem = psutil.virtual_memory()
        snapshot['ram_used_gb'] = round(mem.used / (1024**3), 2)
        snapshot['ram_total_gb'] = round(mem.total / (1024**3), 2)

        swap = psutil.swap_memory()
        snapshot['swap_used_gb'] = round(swap.used / (1024**3), 2)
        snapshot['swap_percent'] = swap.percent

    # GPU memory if available
    if TORCH_AVAILABLE and torch.cuda.is_available():
        try:
            gpu_idx = int(os.environ.get('CUDA_VISIBLE_DEVICES', '0').split(',')[0])
            allocated = torch.cuda.memory_allocated(gpu_idx)
            total = torch.cuda.get_device_properties(gpu_idx).total_memory
            snapshot['gpu_used_gb'] = round(allocated / (1024**3), 2)
            snapshot['gpu_total_gb'] = round(total / (1024**3), 2)
        except Exception:
            pass

    return snapshot


def estimate_training_memory(
    model_params_millions: int,
    batch_size: int = 1,
    seq_length: int = 4096,
    use_4bit: bool = False,
    use_gradient_checkpointing: bool = True,
) -> Dict[str, float]:
    """
    Estimate GPU memory requirements for training.

    Based on: https://huggingface.co/docs/transformers/perf_train_gpu_one

    Args:
        model_params_millions: Model parameters in millions (e.g., 270 for 270M)
        batch_size: Training batch size
        seq_length: Maximum sequence length
        use_4bit: Whether using QLoRA 4-bit quantization
        use_gradient_checkpointing: Whether gradient checkpointing is enabled

    Returns:
        Dict with model_memory_gb, activation_memory_gb, optimizer_memory_gb, total_estimated_gb
    """
    params = model_params_millions * 1e6

    # Model memory
    if use_4bit:
        bytes_per_param = 0.5  # 4-bit = 0.5 bytes
    else:
        bytes_per_param = 2  # bf16/fp16 = 2 bytes

    model_memory_gb = (params * bytes_per_param) / (1024**3)

    # Gradient memory (same size as model in fp16)
    gradient_memory_gb = (params * 2) / (1024**3)

    # Optimizer memory (Adam: 2 states per param in fp32 = 8 bytes)
    # LoRA reduces this significantly - estimate 5% of full
    optimizer_memory_gb = (params * 8 * 0.05) / (1024**3)

    # Activation memory (rough estimate)
    hidden_size = 1024  # Approximate for 270M model
    num_layers = 18  # Approximate

    if use_gradient_checkpointing:
        # Only store activations for sqrt(layers)
        activation_factor = (num_layers ** 0.5) / num_layers
    else:
        activation_factor = 1.0

    activation_bytes = batch_size * seq_length * hidden_size * num_layers * 2 * activation_factor
    activation_memory_gb = activation_bytes / (1024**3)

    total = model_memory_gb + gradient_memory_gb + optimizer_memory_gb + activation_memory_gb

    return {
        'model_memory_gb': round(model_memory_gb, 2),
        'gradient_memory_gb': round(gradient_memory_gb, 2),
        'optimizer_memory_gb': round(optimizer_memory_gb, 2),
        'activation_memory_gb': round(activation_memory_gb, 2),
        'total_estimated_gb': round(total, 2),
    }


def check_memory_feasibility(
    required_gb: float,
    gpu_index: int = 0,
    ram_headroom_gb: float = 4.0,
    swap_warning_percent: float = 50.0,
) -> Dict[str, Any]:
    """
    Check if training is feasible with current memory.

    Args:
        required_gb: Estimated required GPU memory in GB
        gpu_index: GPU index to check
        ram_headroom_gb: Minimum free RAM to maintain
        swap_warning_percent: Warn if swap usage exceeds this

    Returns:
        Dict with feasible, available_gb, and optional warnings
    """
    result = {
        'feasible': True,
        'available_gb': 0.0,
        'required_gb': required_gb,
    }

    warnings = []

    # Check GPU memory
    if TORCH_AVAILABLE and torch.cuda.is_available():
        try:
            props = torch.cuda.get_device_properties(gpu_index)
            available = props.total_memory / (1024**3)
            result['available_gb'] = round(available, 2)

            if required_gb > available * 0.9:  # 90% threshold
                result['feasible'] = False
                warnings.append(f"Required {required_gb:.1f}GB exceeds 90% of available {available:.1f}GB")
        except Exception as e:
            warnings.append(f"Could not check GPU memory: {e}")
    else:
        warnings.append("CUDA not available, cannot check GPU memory")
        result['feasible'] = False

    # Check RAM and swap
    if PSUTIL_AVAILABLE:
        mem = psutil.virtual_memory()
        free_ram_gb = mem.available / (1024**3)

        if free_ram_gb < ram_headroom_gb:
            warnings.append(f"Low RAM: {free_ram_gb:.1f}GB free, recommend {ram_headroom_gb}GB minimum")

        swap = psutil.swap_memory()
        if swap.percent > swap_warning_percent:
            warnings.append(f"High swap usage: {swap.percent:.0f}% (>{swap_warning_percent}%)")

    if warnings:
        result['warning'] = '; '.join(warnings)

    return result


def print_memory_report():
    """Print a formatted memory report to stdout."""
    snapshot = get_memory_snapshot()

    print("\n" + "=" * 50)
    print("MEMORY REPORT")
    print("=" * 50)
    print(f"CPU Usage:    {snapshot['cpu_percent']:.1f}%")
    print(f"RAM:          {snapshot['ram_used_gb']:.1f} / {snapshot['ram_total_gb']:.1f} GB")
    print(f"Swap:         {snapshot['swap_used_gb']:.1f} GB ({snapshot['swap_percent']:.0f}%)")

    if 'gpu_used_gb' in snapshot:
        print(f"GPU Memory:   {snapshot['gpu_used_gb']:.1f} / {snapshot['gpu_total_gb']:.1f} GB")

    if snapshot['swap_percent'] > 50:
        print("\n⚠️  WARNING: High swap usage may impact training performance")

    print("=" * 50 + "\n")
```

**Step 5: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI\Deploy\functiongemma-finetune && uv run pip install psutil && uv run pytest test_memory_profiler.py -v`
Expected: PASS (4 tests)

**Step 6: Commit**

```bash
git add Deploy/functiongemma-finetune/memory_profiler.py Deploy/functiongemma-finetune/test_memory_profiler.py Deploy/functiongemma-finetune/requirements.txt
git commit -m "feat(training): add memory profiler with GPU/RAM/swap monitoring"
```

---

### Task 9: Create Tool Parameter Validation

**Agent:** `powershell-pro`
**Dependencies:** Task 3 (Resolve-PcaiPath)
**Parallel Group:** 3B

**Files:**
- Create: `Modules/PC-AI.LLM/Private/Validate-ToolParameters.ps1`
- Test: `Tests/Unit/Validate-ToolParameters.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/Validate-ToolParameters.Tests.ps1
BeforeAll {
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM'
    . (Join-Path $ModuleRoot 'Private\Validate-ToolParameters.ps1')
}

Describe 'Validate-ToolParameters' {
    Context 'Required parameters' {
        It 'Should pass when all required params present' {
            $schema = @{
                required = @('name')
                properties = @{ name = @{ type = 'string' } }
            }
            $params = @{ name = 'test' }

            $result = Test-ToolParameters -Schema $schema -Parameters $params
            $result.Valid | Should -BeTrue
        }

        It 'Should fail when required param missing' {
            $schema = @{
                required = @('name')
                properties = @{ name = @{ type = 'string' } }
            }
            $params = @{}

            $result = Test-ToolParameters -Schema $schema -Parameters $params
            $result.Valid | Should -BeFalse
            $result.Errors | Should -Contain "Missing required parameter: name"
        }
    }

    Context 'Type validation' {
        It 'Should validate string type' {
            $schema = @{
                properties = @{ name = @{ type = 'string' } }
            }
            $params = @{ name = 123 }

            $result = Test-ToolParameters -Schema $schema -Parameters $params
            $result.Valid | Should -BeFalse
        }

        It 'Should validate enum values' {
            $schema = @{
                properties = @{
                    mode = @{
                        type = 'string'
                        enum = @('check', 'repair')
                    }
                }
            }
            $params = @{ mode = 'invalid' }

            $result = Test-ToolParameters -Schema $schema -Parameters $params
            $result.Valid | Should -BeFalse
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Validate-ToolParameters.Tests.ps1 -Output Detailed`
Expected: FAIL with "Test-ToolParameters is not recognized"

**Step 3: Write minimal implementation**

```powershell
# Modules/PC-AI.LLM/Private/Validate-ToolParameters.ps1
#Requires -Version 5.1

<#
.SYNOPSIS
    Validates tool parameters against JSON Schema-style definitions.
#>

function Test-ToolParameters {
    <#
    .SYNOPSIS
        Validates parameters against a tool schema.

    .PARAMETER Schema
        The tool parameter schema (from pcai-tools.json)

    .PARAMETER Parameters
        The actual parameters provided

    .OUTPUTS
        PSCustomObject with Valid (bool) and Errors (array)
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Schema,

        [Parameter(Mandatory)]
        [hashtable]$Parameters
    )

    $errors = @()

    # Check required parameters
    if ($Schema.required) {
        foreach ($req in $Schema.required) {
            if (-not $Parameters.ContainsKey($req)) {
                $errors += "Missing required parameter: $req"
            }
        }
    }

    # Validate each provided parameter
    if ($Schema.properties) {
        foreach ($key in $Parameters.Keys) {
            $value = $Parameters[$key]
            $propSchema = $Schema.properties[$key]

            if (-not $propSchema) {
                # Unknown parameter - could warn but don't fail
                continue
            }

            # Type validation
            if ($propSchema.type) {
                $typeError = Test-ParameterType -Value $value -ExpectedType $propSchema.type -ParamName $key
                if ($typeError) { $errors += $typeError }
            }

            # Enum validation
            if ($propSchema.enum -and $value) {
                if ($value -notin $propSchema.enum) {
                    $allowed = $propSchema.enum -join ', '
                    $errors += "Parameter '$key' value '$value' not in allowed values: $allowed"
                }
            }
        }
    }

    return [PSCustomObject]@{
        Valid = ($errors.Count -eq 0)
        Errors = $errors
        ParameterCount = $Parameters.Count
    }
}

function Test-ParameterType {
    <#
    .SYNOPSIS
        Validates a single parameter's type.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [string]$ExpectedType,

        [Parameter(Mandatory)]
        [string]$ParamName
    )

    $actualType = $Value.GetType().Name

    switch ($ExpectedType) {
        'string' {
            if ($Value -isnot [string]) {
                return "Parameter '$ParamName' expected string, got $actualType"
            }
        }
        'integer' {
            if ($Value -isnot [int] -and $Value -isnot [long]) {
                return "Parameter '$ParamName' expected integer, got $actualType"
            }
        }
        'number' {
            if ($Value -isnot [int] -and $Value -isnot [long] -and $Value -isnot [double] -and $Value -isnot [decimal]) {
                return "Parameter '$ParamName' expected number, got $actualType"
            }
        }
        'boolean' {
            if ($Value -isnot [bool]) {
                return "Parameter '$ParamName' expected boolean, got $actualType"
            }
        }
        'array' {
            if ($Value -isnot [array]) {
                return "Parameter '$ParamName' expected array, got $actualType"
            }
        }
        'object' {
            if ($Value -isnot [hashtable] -and $Value -isnot [PSCustomObject]) {
                return "Parameter '$ParamName' expected object, got $actualType"
            }
        }
    }

    return $null
}

function ConvertTo-ValidatedToolCall {
    <#
    .SYNOPSIS
        Validates and normalizes a tool call from LLM output.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ToolName,

        [Parameter()]
        [object]$Arguments,

        [Parameter(Mandatory)]
        [array]$ToolDefinitions
    )

    # Find tool definition
    $toolDef = $ToolDefinitions | Where-Object {
        $_.function.name -eq $ToolName
    } | Select-Object -First 1

    if (-not $toolDef) {
        return [PSCustomObject]@{
            Valid = $false
            ToolName = $ToolName
            Arguments = $Arguments
            Error = "Unknown tool: $ToolName"
        }
    }

    # Convert arguments to hashtable
    $argHash = @{}
    if ($Arguments -is [hashtable]) {
        $argHash = $Arguments
    } elseif ($Arguments -is [PSCustomObject]) {
        foreach ($prop in $Arguments.PSObject.Properties) {
            $argHash[$prop.Name] = $prop.Value
        }
    }

    # Validate against schema
    $schema = $toolDef.function.parameters
    $validation = Test-ToolParameters -Schema $schema -Parameters $argHash

    return [PSCustomObject]@{
        Valid = $validation.Valid
        ToolName = $ToolName
        Arguments = $argHash
        Errors = $validation.Errors
        ToolDefinition = $toolDef
    }
}
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\Validate-ToolParameters.Tests.ps1 -Output Detailed`
Expected: PASS (4 tests)

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Private/Validate-ToolParameters.ps1 Tests/Unit/Validate-ToolParameters.Tests.ps1
git commit -m "feat(llm): add tool parameter validation against JSON Schema"
```

---

### Task 10: Create Structured Logging

**Agent:** `powershell-pro`
**Dependencies:** Task 3 (Resolve-PcaiPath)
**Parallel Group:** 3C

**Files:**
- Create: `Modules/PC-AI.LLM/Private/LLM-Logging.ps1`
- Test: `Tests/Unit/LLM-Logging.Tests.ps1`

**Step 1: Write the failing test**

```powershell
# Tests/Unit/LLM-Logging.Tests.ps1
BeforeAll {
    $ModuleRoot = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM'
    . (Join-Path $ModuleRoot 'Private\LLM-Logging.ps1')

    $script:TestLogPath = Join-Path $env:TEMP 'test-llm-router.log'
}

AfterAll {
    Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
}

Describe 'LLM-Logging' {
    BeforeEach {
        Remove-Item $script:TestLogPath -Force -ErrorAction SilentlyContinue
        Set-LLMLogPath -Path $script:TestLogPath
    }

    Context 'Write-LLMLog' {
        It 'Should write JSON log entries' {
            Write-LLMLog -Level Info -Message "Test message" -Data @{ foo = 'bar' }

            $content = Get-Content $script:TestLogPath -Raw | ConvertFrom-Json
            $content.level | Should -Be 'Info'
            $content.message | Should -Be 'Test message'
            $content.data.foo | Should -Be 'bar'
        }

        It 'Should include timestamp' {
            Write-LLMLog -Level Debug -Message "Timestamp test"

            $content = Get-Content $script:TestLogPath -Raw | ConvertFrom-Json
            $content.timestamp | Should -Match '^\d{4}-\d{2}-\d{2}'
        }
    }

    Context 'Log levels' {
        It 'Should respect minimum log level' {
            Set-LLMLogLevel -Level Warning

            Write-LLMLog -Level Debug -Message "Should not appear"
            Write-LLMLog -Level Warning -Message "Should appear"

            $content = Get-Content $script:TestLogPath -Raw
            $content | Should -Not -Match 'Should not appear'
            $content | Should -Match 'Should appear'
        }
    }
}
```

**Step 2: Run test to verify it fails**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\LLM-Logging.Tests.ps1 -Output Detailed`
Expected: FAIL with "Write-LLMLog is not recognized"

**Step 3: Write minimal implementation**

```powershell
# Modules/PC-AI.LLM/Private/LLM-Logging.ps1
#Requires -Version 5.1

<#
.SYNOPSIS
    Structured JSON logging for LLM router operations.
#>

# Module-scoped log configuration
$script:LLMLogConfig = @{
    Path = $null
    Level = 'Info'
    LevelOrder = @{
        'Debug' = 0
        'Info' = 1
        'Warning' = 2
        'Error' = 3
    }
}

function Set-LLMLogPath {
    <#
    .SYNOPSIS
        Sets the log file path.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $script:LLMLogConfig.Path = $Path

    # Ensure directory exists
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Set-LLMLogLevel {
    <#
    .SYNOPSIS
        Sets the minimum log level.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level
    )

    $script:LLMLogConfig.Level = $Level
}

function Write-LLMLog {
    <#
    .SYNOPSIS
        Writes a structured JSON log entry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [hashtable]$Data,

        [Parameter()]
        [string]$Operation,

        [Parameter()]
        [string]$Provider
    )

    # Check log level
    $currentLevelOrder = $script:LLMLogConfig.LevelOrder[$script:LLMLogConfig.Level]
    $messageLevelOrder = $script:LLMLogConfig.LevelOrder[$Level]

    if ($messageLevelOrder -lt $currentLevelOrder) {
        return
    }

    # Build log entry
    $entry = [ordered]@{
        timestamp = Get-Date -Format 'o'
        level = $Level
        message = $Message
    }

    if ($Operation) { $entry['operation'] = $Operation }
    if ($Provider) { $entry['provider'] = $Provider }
    if ($Data) { $entry['data'] = $Data }

    $json = $entry | ConvertTo-Json -Compress -Depth 10

    # Write to file
    if ($script:LLMLogConfig.Path) {
        Add-Content -Path $script:LLMLogConfig.Path -Value $json -Encoding UTF8
    }

    # Also write to verbose stream
    Write-Verbose "[$Level] $Message"
}

function Write-LLMRouterLog {
    <#
    .SYNOPSIS
        Logs a router decision with full context.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RequestId,

        [Parameter()]
        [string]$UserPrompt,

        [Parameter()]
        [array]$ToolCalls,

        [Parameter()]
        [array]$ToolResults,

        [Parameter()]
        [string]$Provider,

        [Parameter()]
        [double]$LatencyMs,

        [Parameter()]
        [bool]$Success = $true,

        [Parameter()]
        [string]$Error
    )

    $data = @{
        requestId = $RequestId
        promptLength = if ($UserPrompt) { $UserPrompt.Length } else { 0 }
        toolCallCount = if ($ToolCalls) { $ToolCalls.Count } else { 0 }
        toolResultCount = if ($ToolResults) { $ToolResults.Count } else { 0 }
        latencyMs = $LatencyMs
        success = $Success
    }

    if ($Error) { $data['error'] = $Error }

    $level = if ($Success) { 'Info' } else { 'Error' }
    $msg = if ($Success) { "Router completed" } else { "Router failed: $Error" }

    Write-LLMLog -Level $level -Message $msg -Operation 'router' -Provider $Provider -Data $data
}

function Get-LLMLogPath {
    <#
    .SYNOPSIS
        Gets the current log file path.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()

    if ($script:LLMLogConfig.Path) {
        return $script:LLMLogConfig.Path
    }

    # Default path
    $root = if ($env:PCAI_ROOT) { $env:PCAI_ROOT } else { 'C:\Users\david\PC_AI' }
    return Join-Path $root 'Reports\Logs\llm-router.log'
}

# Initialize default log path
$defaultLogPath = Get-LLMLogPath
if (-not $script:LLMLogConfig.Path) {
    Set-LLMLogPath -Path $defaultLogPath
}
```

**Step 4: Run test to verify it passes**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Unit\LLM-Logging.Tests.ps1 -Output Detailed`
Expected: PASS (3 tests)

**Step 5: Commit**

```bash
git add Modules/PC-AI.LLM/Private/LLM-Logging.ps1 Tests/Unit/LLM-Logging.Tests.ps1
git commit -m "feat(llm): add structured JSON logging for router operations"
```

---

### Task 11: End-to-End Integration Tests

**Agent:** `test-runner`
**Dependencies:** All previous tasks
**Parallel Group:** 3D

**Files:**
- Create: `Tests/Integration/LLM-Router.E2E.Tests.ps1`
- Modify: `Tests/Integration/Verification.E2E.ps1`

**Step 1: Create E2E test file**

```powershell
# Tests/Integration/LLM-Router.E2E.Tests.ps1
<#
.SYNOPSIS
    End-to-end integration tests for LLM router optimizations.
#>

BeforeAll {
    $ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    Import-Module (Join-Path $ProjectRoot 'Modules\PC-AI.LLM\PC-AI.LLM.psd1') -Force
}

Describe 'LLM Router E2E Tests' -Tag 'E2E', 'LLM' {
    Context 'Path Resolution' {
        It 'Should resolve project root correctly' {
            $root = Resolve-PcaiPath -PathType 'Root'
            Test-Path $root | Should -BeTrue
        }

        It 'Should find pcai-tools.json' {
            $tools = Resolve-PcaiPath -PathType 'Tools'
            Test-Path $tools | Should -BeTrue
        }
    }

    Context 'Provider Health' {
        It 'Should cache health check results' {
            Reset-ProviderHealthCache

            # First call should hit the network
            $start = Get-Date
            $first = Get-CachedProviderHealth -Provider 'ollama' -TimeoutSeconds 2
            $firstDuration = (Get-Date) - $start

            # Second call should use cache (much faster)
            $start = Get-Date
            $second = Get-CachedProviderHealth -Provider 'ollama' -TimeoutSeconds 2
            $secondDuration = (Get-Date) - $start

            $secondDuration.TotalMilliseconds | Should -BeLessThan ($firstDuration.TotalMilliseconds * 0.5)
        }
    }

    Context 'Graceful Degradation' {
        It 'Should work with BypassRouter flag' {
            # This should work even if vLLM is not running
            $result = Invoke-LLMChatRouted -Message "Hello" -BypassRouter -Provider 'ollama' -ErrorAction SilentlyContinue

            if ($result) {
                $result.DegradedMode | Should -BeTrue
            }
        }
    }

    Context 'Tool Validation' {
        It 'Should validate tool parameters from pcai-tools.json' {
            $toolsPath = Resolve-PcaiPath -PathType 'Tools'
            $tools = Get-Content $toolsPath | ConvertFrom-Json

            # Test GetSystemInfo tool
            $schema = ($tools.tools | Where-Object { $_.function.name -eq 'GetSystemInfo' }).function.parameters

            $validParams = @{ category = 'Storage' }
            $result = Test-ToolParameters -Schema $schema -Parameters $validParams
            $result.Valid | Should -BeTrue

            $invalidParams = @{ category = 'Invalid' }
            $result = Test-ToolParameters -Schema $schema -Parameters $invalidParams
            $result.Valid | Should -BeFalse
        }
    }

    Context 'Logging' {
        It 'Should write structured logs' {
            $testLogPath = Join-Path $env:TEMP 'e2e-llm-test.log'
            Set-LLMLogPath -Path $testLogPath

            Write-LLMRouterLog -RequestId 'test-123' -Provider 'ollama' -LatencyMs 100 -Success $true

            $content = Get-Content $testLogPath -Raw | ConvertFrom-Json
            $content.data.requestId | Should -Be 'test-123'

            Remove-Item $testLogPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe 'vLLM Docker Integration' -Tag 'E2E', 'Docker' {
    BeforeAll {
        $script:DockerAvailable = $false
        try {
            docker info 2>&1 | Out-Null
            $script:DockerAvailable = $true
        } catch {}
    }

    Context 'Docker Configuration' -Skip:(-not $script:DockerAvailable) {
        It 'Should have valid docker-compose.yml' {
            $composePath = Join-Path $ProjectRoot 'Deploy\docker\vllm\docker-compose.yml'
            Test-Path $composePath | Should -BeTrue

            # Validate YAML
            $result = docker compose -f $composePath config 2>&1
            $LASTEXITCODE | Should -Be 0
        }

        It 'Should have .env.example template' {
            $envExample = Join-Path $ProjectRoot 'Deploy\docker\vllm\.env.example'
            Test-Path $envExample | Should -BeTrue
        }
    }
}

Describe 'FunctionGemma Training Pipeline' -Tag 'E2E', 'Training' {
    Context 'Configuration' {
        It 'Should have config.py module' {
            $configPath = Join-Path $ProjectRoot 'Deploy\functiongemma-finetune\config.py'
            Test-Path $configPath | Should -BeTrue
        }

        It 'Should have memory profiler' {
            $profilerPath = Join-Path $ProjectRoot 'Deploy\functiongemma-finetune\memory_profiler.py'
            Test-Path $profilerPath | Should -BeTrue
        }
    }
}
```

**Step 2: Run E2E tests**

Run: `cd C:\Users\david\PC_AI && Invoke-Pester Tests\Integration\LLM-Router.E2E.Tests.ps1 -Output Detailed -Tag E2E`
Expected: PASS (with some skips for Docker if not running)

**Step 3: Commit**

```bash
git add Tests/Integration/LLM-Router.E2E.Tests.ps1
git commit -m "test(e2e): add comprehensive LLM router integration tests"
```

---

## POST-IMPLEMENTATION

### Task 12: Update Module Exports

**Agent:** `powershell-pro`
**Dependencies:** All Phase 3 tasks

**Files:**
- Modify: `Modules/PC-AI.LLM/PC-AI.LLM.psm1`

Add new functions to Export-ModuleMember (around line 127):

```powershell
Export-ModuleMember -Function @(
    # Existing exports...
    'Get-LLMStatus'
    'Send-OllamaRequest'
    'Invoke-LLMChat'
    'Invoke-LLMChatRouted'
    'Invoke-LLMChatTui'
    'Invoke-FunctionGemmaReAct'
    'Invoke-PCDiagnosis'
    'Set-LLMConfig'
    'Set-LLMProviderOrder'
    'Invoke-SmartDiagnosis'
    'Invoke-NativeSearch'
    'Invoke-DocSearch'
    'Get-SystemInfoTool'
    'Invoke-LogSearch'
    # New exports
    'Resolve-PcaiPath'
    'Get-CachedProviderHealth'
    'Reset-ProviderHealthCache'
    'Set-ProviderHealthCacheTTL'
    'Test-ToolParameters'
    'Write-LLMLog'
    'Set-LLMLogPath'
    'Set-LLMLogLevel'
)
```

**Commit:**

```bash
git add Modules/PC-AI.LLM/PC-AI.LLM.psm1
git commit -m "feat(llm): export new path, health, validation, and logging functions"
```

---

## Verification Checklist

```powershell
# 1. Run all unit tests
Invoke-Pester Tests\Unit -Output Detailed

# 2. Run E2E tests
Invoke-Pester Tests\Integration\LLM-Router.E2E.Tests.ps1 -Output Detailed

# 3. Verify config.py works
cd Deploy\functiongemma-finetune
uv run python -c "from config import get_config; print(get_config().pcai_root)"

# 4. Verify memory profiler
uv run python -c "from memory_profiler import print_memory_report; print_memory_report()"

# 5. Test Docker config
cd Deploy\docker\vllm
docker compose config

# 6. Test LLM module
Import-Module .\Modules\PC-AI.LLM\PC-AI.LLM.psd1 -Force
Get-LLMStatus
Resolve-PcaiPath -PathType Tools
Get-CachedProviderHealth -Provider ollama -Verbose

# 7. Test graceful degradation
Invoke-LLMChatRouted -Message "Test" -BypassRouter -Verbose
```

---

## Summary

| Phase | Tasks | Agents | Estimated Tokens |
|-------|-------|--------|------------------|
| 1: Foundation | 3 | python-pro, deployment-engineer, powershell-pro | ~33K |
| 2: Training & Reliability | 4 | python-pro, powershell-pro (x3) | ~39K |
| 3: Observability | 4 | python-pro, powershell-pro (x2), test-runner | ~43K |
| Post | 1 | powershell-pro | ~5K |
| **Total** | **12** | **4 unique agents** | **~120K** |

**Parallelization Savings:** Running Phase 1 in parallel saves ~66% time; Phase 2 saves ~75% time; Phase 3 saves ~75% time.

### Agent Capabilities Leveraged

| Agent | Strengths Used |
|-------|----------------|
| `python-pro` | PyTorch, transformers, peft, dataclasses, type hints |
| `deployment-engineer` | Docker Compose, multi-GPU config, healthchecks |
| `powershell-pro` | Module development, Pester tests, .NET integration, pipeline optimization |
| `test-runner` | E2E test orchestration, Pester execution |
| `code-reviewer` | Cross-language review, architecture validation |
