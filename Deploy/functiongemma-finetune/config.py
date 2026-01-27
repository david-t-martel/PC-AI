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
