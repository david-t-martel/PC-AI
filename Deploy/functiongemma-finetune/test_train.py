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
