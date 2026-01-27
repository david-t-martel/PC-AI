import argparse
from typing import Any, Dict, List, Optional
import json

from datasets import Dataset
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from transformers.utils import get_json_schema

try:
    import orjson
except ImportError:  # pragma: no cover
    orjson = None


def json_dumps(obj: Any) -> str:
    if orjson:
        return orjson.dumps(obj).decode("utf-8")
    return json.dumps(obj, ensure_ascii=False)


def pcai_run_wsl_network_tool(mode: str) -> str:
    """
    Run WSL network toolkit with a specified mode.

    Args:
        mode: Execution mode for the WSL network toolkit (check|diagnose|repair|full).
    """
    return "OK"


def pcai_get_wsl_health() -> str:
    """Collect WSL and Docker environment health summary."""
    return "OK"


def pcai_restart_wsl() -> str:
    """Restart WSL to reinitialize networking and services."""
    return "OK"


def pcai_get_docker_status() -> str:
    """Return Docker Desktop health and runtime status."""
    return "OK"


class ToolCallFunction(BaseModel):
    model_config = ConfigDict(extra="forbid")
    name: str
    arguments: Dict[str, Any]


class ToolCall(BaseModel):
    model_config = ConfigDict(extra="forbid")
    type: str = "function"
    function: ToolCallFunction


class Message(BaseModel):
    model_config = ConfigDict(extra="forbid")
    role: str
    content: Optional[str] = None
    tool_calls: Optional[List[ToolCall]] = None


class Conversation(BaseModel):
    model_config = ConfigDict(extra="forbid")
    messages: List[Message]
    tools: List[Dict[str, Any]] = Field(default_factory=list)


class DatasetConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")
    output: str


def build_dataset() -> Dataset:
    samples = [
        {
            "user_content": "Run a WSL network diagnosis and summarize any failures.",
            "tool_name": "pcai_run_wsl_network_tool",
            "tool_arguments": {"mode": "diagnose"},
        },
        {
            "user_content": "Check the WSL/Docker environment health and report status.",
            "tool_name": "pcai_get_wsl_health",
            "tool_arguments": {},
        },
        {
            "user_content": "Restart WSL because networking is stuck.",
            "tool_name": "pcai_restart_wsl",
            "tool_arguments": {},
        },
        {
            "user_content": "Check Docker Desktop health and return a summary.",
            "tool_name": "pcai_get_docker_status",
            "tool_arguments": {},
        },
    ]

    tools = [
        get_json_schema(pcai_run_wsl_network_tool),
        get_json_schema(pcai_get_wsl_health),
        get_json_schema(pcai_restart_wsl),
        get_json_schema(pcai_get_docker_status),
    ]

    default_system_msg = "You are a model that can do function calling with the following functions"

    def create_conversation(sample: Dict[str, Any]) -> Dict[str, Any]:
        conversation = Conversation(
            messages=[
                Message(role="developer", content=default_system_msg),
                Message(role="user", content=sample["user_content"]),
                Message(
                    role="assistant",
                    tool_calls=[
                        ToolCall(
                            function=ToolCallFunction(
                                name=sample["tool_name"],
                                arguments=sample["tool_arguments"],
                            )
                        )
                    ],
                ),
            ],
            tools=tools,
        )
        return conversation.model_dump(mode="json", exclude_none=True)

    dataset = Dataset.from_list(samples)
    dataset = dataset.map(create_conversation, remove_columns=dataset.features, batched=False)
    return dataset


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, help="Path to output JSONL file")
    args = parser.parse_args()

    try:
        cfg = DatasetConfig(output=args.output)
    except ValidationError as exc:
        raise SystemExit(str(exc))

    dataset = build_dataset()

    with open(cfg.output, "w", encoding="utf-8") as f:
        for item in dataset:
            f.write(json_dumps(item) + "\n")

    print(f"Wrote {len(dataset)} examples to {cfg.output}")


if __name__ == "__main__":
    main()
