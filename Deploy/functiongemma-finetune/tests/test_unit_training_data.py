import json
from pathlib import Path

import pytest

import generate_training_data


@pytest.mark.unit
def test_generate_training_data(tmp_path, tool_config_path):
    output = tmp_path / "train.jsonl"
    vectors = tmp_path / "vectors.json"

    generate_training_data.main = generate_training_data.main  # keep linter quiet

    # Call generator directly
    args = [
        "--tools",
        tool_config_path,
        "--output",
        str(output),
        "--test-vectors",
        str(vectors),
        "--max-cases",
        "4",
    ]

    # Emulate CLI
    import sys
    old_argv = sys.argv
    sys.argv = ["generate_training_data.py", *args]
    try:
        generate_training_data.main()
    finally:
        sys.argv = old_argv

    assert output.exists()
    assert vectors.exists()
    lines = output.read_text(encoding="utf-8").strip().splitlines()
    assert lines, "No training data produced"
    first = json.loads(lines[0])
    assert "messages" in first and "tools" in first
