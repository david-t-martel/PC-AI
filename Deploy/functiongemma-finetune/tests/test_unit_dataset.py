import json
from pathlib import Path

import pytest

import prepare_dataset


@pytest.mark.unit
def test_prepare_dataset_generates_examples(tmp_path):
    output = tmp_path / "train.jsonl"
    prepare_dataset.main = prepare_dataset.main  # keep linter quiet

    dataset = prepare_dataset.build_dataset()
    assert len(dataset) > 0

    with output.open("w", encoding="utf-8") as f:
        for item in dataset:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    lines = output.read_text(encoding="utf-8").strip().splitlines()
    assert lines, "No JSONL lines written"

    first = json.loads(lines[0])
    assert "messages" in first
    assert "tools" in first
