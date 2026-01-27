import argparse
import json
import time
from pathlib import Path
from typing import Any, Dict, Optional

from pydantic import BaseModel, ConfigDict, Field, ValidationError

try:
    import httpx
except ImportError:  # pragma: no cover
    httpx = None

import urllib.request


def load_tools(path: str) -> Dict[str, Any]:
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)["tools"]


def chat_completion(base_url: str, model: str, messages, tools, timeout: int = 120):
    payload = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "tool_choice": "auto",
        "temperature": 0.2,
    }

    if httpx:
        with httpx.Client(timeout=timeout) as client:
            resp = client.post(f"{base_url.rstrip('/')}/v1/chat/completions", json=payload)
            resp.raise_for_status()
            return resp.json()

    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        f"{base_url.rstrip('/')}/v1/chat/completions",
        data=data,
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_metrics(base_url: str, timeout: int = 10) -> Dict[str, float]:
    metrics_url = f"{base_url.rstrip('/')}/metrics"
    if httpx:
        with httpx.Client(timeout=timeout) as client:
            text = client.get(metrics_url).text
    else:
        req = urllib.request.Request(metrics_url)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            text = resp.read().decode("utf-8")

    metrics: Dict[str, float] = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        if line.startswith("vllm:"):
            try:
                name, value = line.split(" ")
                metric = name.split("{")[0]
                metrics[metric] = float(value)
            except ValueError:
                continue
    return metrics


class EvalConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    base_url: str = "http://127.0.0.1:8000"
    model: str = "functiongemma-270m-it"
    tools: str = r"C:\Users\david\PC_AI\Config\pcai-tools.json"
    prompt: str
    timeout: int = 120
    show_metrics: bool = False
    system_prompt: Optional[str] = None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--model", default="functiongemma-270m-it")
    parser.add_argument("--tools", default=r"C:\Users\david\PC_AI\Config\pcai-tools.json")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--show-metrics", action="store_true")
    parser.add_argument("--system-prompt", default=None)
    args = parser.parse_args()

    try:
        cfg = EvalConfig(
            base_url=args.base_url,
            model=args.model,
            tools=args.tools,
            prompt=args.prompt,
            timeout=args.timeout,
            show_metrics=args.show_metrics,
            system_prompt=args.system_prompt,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))

    tools = load_tools(cfg.tools)
    messages = []
    if cfg.system_prompt and Path(cfg.system_prompt).exists():
        system_text = Path(cfg.system_prompt).read_text(encoding="utf-8")
        messages.append({"role": "developer", "content": system_text})
    messages.append({"role": "user", "content": cfg.prompt})

    metrics_before = fetch_metrics(cfg.base_url) if cfg.show_metrics else None
    start = time.time()
    result = chat_completion(cfg.base_url, cfg.model, messages, tools, timeout=cfg.timeout)
    elapsed = time.time() - start
    metrics_after = fetch_metrics(cfg.base_url) if cfg.show_metrics else None

    choice = result.get("choices", [])[0]
    message = choice.get("message", {})

    if cfg.show_metrics and metrics_before and metrics_after:
        prompt_delta = metrics_after.get("vllm:prompt_tokens_total", 0.0) - metrics_before.get("vllm:prompt_tokens_total", 0.0)
        gen_delta = metrics_after.get("vllm:generation_tokens_total", 0.0) - metrics_before.get("vllm:generation_tokens_total", 0.0)
        tps = (prompt_delta + gen_delta) / elapsed if elapsed > 0 else 0
        message["metrics"] = {
            "elapsed_sec": round(elapsed, 3),
            "prompt_tokens": int(prompt_delta),
            "generation_tokens": int(gen_delta),
            "tokens_per_sec": round(tps, 2),
        }

    print(json.dumps(message, indent=2))


if __name__ == "__main__":
    main()
