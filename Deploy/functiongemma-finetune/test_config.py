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
