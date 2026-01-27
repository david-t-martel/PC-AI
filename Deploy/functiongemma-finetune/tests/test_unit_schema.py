import json
from pathlib import Path

import pytest


def test_tool_schema_is_valid(tool_config_path: str):
    path = Path(tool_config_path)
    assert path.exists(), f"Missing tool schema file: {path}"

    data = json.loads(path.read_text(encoding="utf-8"))
    assert "tools" in data
    assert isinstance(data["tools"], list)

    names = set()
    for tool in data["tools"]:
        assert tool.get("type") == "function"
        fn = tool.get("function")
        assert fn and "name" in fn
        assert fn["name"].startswith("pcai_")
        assert fn["name"] not in names
        names.add(fn["name"])

        params = fn.get("parameters")
        assert params and params.get("type") == "object"
        assert "properties" in params

        required = set(params.get("required", []))
        for key in required:
            assert key in params["properties"], f"Required param {key} missing properties"


@pytest.mark.unit
def test_tool_schema_contains_descriptions(tool_config_path: str):
    data = json.loads(Path(tool_config_path).read_text(encoding="utf-8"))
    for tool in data["tools"]:
        fn = tool.get("function", {})
        assert fn.get("description"), f"Tool {fn.get('name')} missing description"
        params = fn.get("parameters", {})
        for name, prop in params.get("properties", {}).items():
            assert prop.get("description"), f"Param {name} missing description"
