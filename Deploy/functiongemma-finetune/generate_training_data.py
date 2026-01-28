import argparse
import json
from pathlib import Path
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError
from schema_utils import generate_arg_sets


def load_tools(path: str) -> List[Dict[str, Any]]:
    data = json.loads(Path(path).read_text(encoding="utf-8"))
    return data["tools"]


def build_prompt(tool_name: str, description: str, args: Dict[str, Any]) -> str:
    args_text = json.dumps(args, ensure_ascii=False)
    return f"Use {tool_name} to perform the task: {description}. Arguments: {args_text}"


class GeneratorConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tools_path: str
    output: str
    test_vectors: str
    max_cases: int = 24
    system_prompt: Optional[str] = None
    scenarios: Optional[str] = None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tools", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--test-vectors", required=True)
    parser.add_argument("--max-cases", type=int, default=24)
    parser.add_argument("--system-prompt", default=None)
    parser.add_argument(
        "--scenarios", default=None, help="Optional scenarios JSON for NO_TOOL examples"
    )
    args = parser.parse_args()

    try:
        cfg = GeneratorConfig(
            tools_path=args.tools,
            output=args.output,
            test_vectors=args.test_vectors,
            max_cases=args.max_cases,
            system_prompt=args.system_prompt,
            scenarios=args.scenarios,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))

    tools = load_tools(cfg.tools_path)

    dataset_items = []
    test_vectors = []
    default_system_msg = (
        "You are a model that can do function calling with the following functions"
    )
    if cfg.system_prompt and Path(cfg.system_prompt).exists():
        system_prompt_text = Path(cfg.system_prompt).read_text(encoding="utf-8")
        default_system_msg = f"{system_prompt_text}\n\nYou are a tool-calling router. Use only the provided tools."

    for tool in tools:
        fn = tool["function"]
        name = fn["name"]
        description = fn.get("description", "")
        params = fn.get("parameters", {})

        for args in generate_arg_sets(params, max_cases=cfg.max_cases):
            user_prompt = build_prompt(name, description, args)

            # Context-Aware Optimization: Inject [NATIVE_CONTEXT] placeholder
            # In a real scenario, this would be a JSON string from PcaiCore
            context_aware_prompt = f'[NATIVE_CONTEXT]\n{{"telemetry": "active", "tool": "{name}"}}\n\n[USER_REQUEST]\n{user_prompt}'

            # FunctionGemma/Unsloth Optimization: Reasoning Trace
            # We explicitly teach the model to "think" before "acting".
            # This aligns with the "Reflexion" or "Chain of Thought" Agentic patterns.
            # Ideally, these tokens should be distinct. Here we use <thought>...</thought> as defined in the plan.
            thought_process = (
                f"<thought>\n"
                f'User request: "{user_prompt}".\n'
                f"Reasoning: Tool '{name}' performs \"{description}\".\n"
                f"Decision: I will call '{name}' to satisfy the request.\n"
                f"</thought>\n"
            )

            dataset_items.append(
                {
                    "messages": [
                        # Gemma 2 chat template does not support 'system' role.
                        # We prepend the system instruction to the first user message.
                        {
                            "role": "user",
                            "content": f"{default_system_msg}\n\n{context_aware_prompt}",
                        },
                        {
                            "role": "assistant",  # Standardize to 'assistant' for Unsloth/HuggingFace
                            "content": thought_process,  # The thought is text content
                            "tool_calls": [
                                {
                                    "type": "function",
                                    "function": {
                                        "name": name,
                                        "arguments": args,
                                    },
                                }
                            ],
                        },
                    ],
                    "tools": tools,
                }
            )
            test_vectors.append({"tool": name, "arguments": args})

    if cfg.scenarios and Path(cfg.scenarios).exists():
        raw = json.loads(Path(cfg.scenarios).read_text(encoding="utf-8"))
        items = raw.get("scenarios", raw)
        for scenario in items:
            if scenario.get("tool_name"):
                continue
            dataset_items.append(
                {
                    "messages": [
                        {"role": "developer", "content": default_system_msg},
                        {"role": "user", "content": scenario.get("user_content", "")},
                        {
                            "role": "assistant",
                            "content": scenario.get("assistant_content", "NO_TOOL"),
                        },
                    ],
                    "tools": tools,
                }
            )

    output_path = Path(cfg.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as f:
        for item in dataset_items:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")

    test_vectors_path = Path(cfg.test_vectors)
    test_vectors_path.parent.mkdir(parents=True, exist_ok=True)
    test_vectors_path.write_text(json.dumps(test_vectors, indent=2), encoding="utf-8")

    print(f"Wrote {len(dataset_items)} training examples to {output_path}")
    print(f"Wrote {len(test_vectors)} tool test vectors to {test_vectors_path}")


if __name__ == "__main__":
    main()
