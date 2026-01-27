import argparse
from pathlib import Path
from typing import Any, Dict, List, Optional
import json

from datasets import Dataset
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from schema_utils import generate_arg_sets

try:
    import orjson
except ImportError:  # pragma: no cover
    orjson = None


def json_dumps(obj: Any) -> str:
    if orjson:
        return orjson.dumps(obj).decode("utf-8")
    return json.dumps(obj, ensure_ascii=False)


def load_tools(path: str) -> List[Dict[str, Any]]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data["tools"]


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
    tools_path: str
    diagnose_prompt: str
    chat_prompt: str
    scenarios_path: Optional[str] = None
    include_tool_coverage: bool = True
    max_cases: int = 24


class Scenario(BaseModel):
    model_config = ConfigDict(extra="forbid")

    mode: str
    user_content: str
    tool_name: Optional[str] = None
    tool_arguments: Dict[str, Any] = Field(default_factory=dict)
    assistant_content: Optional[str] = None


def load_prompt(path: str) -> str:
    return Path(path).read_text(encoding="utf-8") if Path(path).exists() else ""


def load_scenarios(path: Optional[str]) -> List[Scenario]:
    if path and Path(path).exists():
        raw = json.loads(Path(path).read_text(encoding="utf-8"))
        items = raw.get("scenarios", raw)
        return [Scenario(**item) for item in items]

    return [
        Scenario(
            mode="diagnose",
            user_content="Run a WSL network diagnosis and summarize any failures.",
            tool_name="pcai_run_wsl_network_tool",
            tool_arguments={"mode": "diagnose"},
        ),
        Scenario(
            mode="diagnose",
            user_content="Check the WSL/Docker environment health and report status.",
            tool_name="pcai_get_wsl_health",
            tool_arguments={},
        ),
        Scenario(
            mode="diagnose",
            user_content="Restart WSL because networking is stuck.",
            tool_name="pcai_restart_wsl",
            tool_arguments={},
        ),
        Scenario(
            mode="diagnose",
            user_content="Check Docker Desktop health and return a summary.",
            tool_name="pcai_get_docker_status",
            tool_arguments={},
        ),
        Scenario(
            mode="chat",
            user_content="Explain what WSL is and when to use it.",
            assistant_content="NO_TOOL",
        ),
        Scenario(
            mode="chat",
            user_content="What does vLLM do and when should I use it?",
            assistant_content="NO_TOOL",
        ),
    ]


def build_system_prompt(mode: str, diagnose_prompt: str, chat_prompt: str) -> str:
    router_rules = (
        "You are a tool-calling router for PC-AI. "
        "Use only the tools provided in the schema. "
        "If a tool call is required, return tool_calls only. "
        "If no tool is needed, respond with NO_TOOL."
    )
    if mode.lower() == "chat":
        return f"{chat_prompt}\n\n{router_rules}"
    return f"{diagnose_prompt}\n\n{router_rules}"


def build_tool_prompt(name: str, description: str, args: Dict[str, Any]) -> str:
    args_text = json.dumps(args, ensure_ascii=False)
    return f"Use {name} to perform the task: {description}. Arguments: {args_text}"


def build_dataset(cfg: DatasetConfig) -> Dataset:
    tools = load_tools(cfg.tools_path)
    scenarios = load_scenarios(cfg.scenarios_path)
    diagnose_prompt = load_prompt(cfg.diagnose_prompt)
    chat_prompt = load_prompt(cfg.chat_prompt)

    samples: List[Dict[str, Any]] = [s.model_dump(mode="json") for s in scenarios]

    if cfg.include_tool_coverage:
        for tool in tools:
            fn = tool["function"]
            name = fn["name"]
            description = fn.get("description", "")
            params = fn.get("parameters", {})
            for args in generate_arg_sets(params, max_cases=cfg.max_cases):
                samples.append(
                    {
                        "mode": "diagnose",
                        "user_content": build_tool_prompt(name, description, args),
                        "tool_name": name,
                        "tool_arguments": args,
                    }
                )

    def create_conversation(sample: Dict[str, Any]) -> Dict[str, Any]:
        scenario = Scenario(**sample)
        system_msg = build_system_prompt(
            scenario.mode,
            diagnose_prompt=diagnose_prompt,
            chat_prompt=chat_prompt,
        )
        messages = [
            Message(role="developer", content=system_msg),
            Message(role="user", content=scenario.user_content),
        ]
        if scenario.tool_name:
            messages.append(
                Message(
                    role="assistant",
                    tool_calls=[
                        ToolCall(
                            function=ToolCallFunction(
                                name=scenario.tool_name,
                                arguments=scenario.tool_arguments,
                            )
                        )
                    ],
                )
            )
        else:
            messages.append(
                Message(role="assistant", content=scenario.assistant_content or "NO_TOOL")
            )
        conversation = Conversation(messages=messages, tools=tools)
        return conversation.model_dump(mode="json", exclude_none=True)

    dataset = Dataset.from_list(samples)
    dataset = dataset.map(create_conversation, remove_columns=dataset.features, batched=False)
    return dataset


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, help="Path to output JSONL file")
    parser.add_argument("--tools", required=True, help="Path to pcai-tools.json")
    parser.add_argument("--diagnose-prompt", required=True, help="Path to DIAGNOSE.md")
    parser.add_argument("--chat-prompt", required=True, help="Path to CHAT.md")
    parser.add_argument("--scenarios", default=None, help="Optional scenarios JSON file")
    parser.add_argument("--no-tool-coverage", action="store_true", help="Skip tool schema coverage generation")
    parser.add_argument("--max-cases", type=int, default=24)
    args = parser.parse_args()

    try:
        cfg = DatasetConfig(
            output=args.output,
            tools_path=args.tools,
            diagnose_prompt=args.diagnose_prompt,
            chat_prompt=args.chat_prompt,
            scenarios_path=args.scenarios,
            include_tool_coverage=not args.no_tool_coverage,
            max_cases=args.max_cases,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))

    dataset = build_dataset(cfg)

    with open(cfg.output, "w", encoding="utf-8") as f:
        for item in dataset:
            f.write(json_dumps(item) + "\n")

    print(f"Wrote {len(dataset)} examples to {cfg.output}")


if __name__ == "__main__":
    main()
