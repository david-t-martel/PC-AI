#!/usr/bin/env python
"""Verify that the new training configuration fields work correctly."""

import sys

from train_functiongemma import parse_args


def test_defaults():
    """Config should have correct Unsloth defaults."""
    # new defaults: 4bit=True, warmup_steps=5
    sys.argv = ["train", "--model", "test", "--train", "test.json", "--output", "out"]
    cfg = parse_args()

    assert cfg.use_4bit is True, f"Expected 4bit True by default, got {cfg.use_4bit}"
    assert cfg.warmup_steps == 5, f"Expected warmup_steps=5, got {cfg.warmup_steps}"
    assert cfg.batch_size == 2, f"Expected batch_size=2, got {cfg.batch_size}"
    print("[PASS] Defaults verified")


def test_disable_4bit():
    """Flag --no-4bit should set use_4bit to False."""
    sys.argv = [
        "train",
        "--model",
        "test",
        "--train",
        "test.json",
        "--output",
        "out",
        "--no-4bit",
    ]
    cfg = parse_args()
    assert cfg.use_4bit is False, f"Expected 4bit False, got {cfg.use_4bit}"
    print("[PASS] Disable 4-bit flag")


def test_resume_checkpoint():
    """Resume from checkpoint should work."""
    sys.argv = [
        "train",
        "--model",
        "test",
        "--train",
        "test.json",
        "--output",
        "out",
        "--resume-from-checkpoint",
        "latest",
    ]
    cfg = parse_args()
    assert cfg.resume_from_checkpoint == "latest", (
        f"Expected 'latest', got {cfg.resume_from_checkpoint}"
    )
    print("[PASS] Resume checkpoint")


if __name__ == "__main__":
    print("Running verification tests...\n")
    try:
        test_defaults()
        test_disable_4bit()
        test_resume_checkpoint()
        print("\n[SUCCESS] All (updated) tests PASSED!")
    except AssertionError as e:
        print(f"\n[FAILED] Test FAILED: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"\n[ERROR] Error: {e}")
        sys.exit(1)
