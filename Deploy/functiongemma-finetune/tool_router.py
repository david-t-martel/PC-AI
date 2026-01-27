import argparse
# DEPRECATED: prefer native C# routing via PcaiOpenAiClient + Invoke-FunctionGemmaReAct.
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
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


def chat_completion(base_url: str, model: str, messages, tools, timeout: int = 120, **overrides):
    payload = {
        "model": model,
        "messages": messages,
        "tools": tools,
        "tool_choice": overrides.get("tool_choice", "auto"),
        "temperature": overrides.get("temperature", 0.2),
    }
    if overrides.get("max_tokens") is not None:
        payload["max_tokens"] = overrides["max_tokens"]

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


class RouterConfig(BaseModel):
    model_config = ConfigDict(extra="forbid")

    host: str = "127.0.0.1"
    port: int = 18010
    base_url: str = "http://127.0.0.1:8000"
    model: str = "functiongemma-270m-it"
    tools: str = r"C:\Users\david\PC_AI\Config\pcai-tools.json"
    timeout: int = 120
    system_prompt: Optional[str] = None


class RouterHandler(BaseHTTPRequestHandler):
    tools = None
    base_url = "http://127.0.0.1:8000"
    model = "functiongemma-270m-it"
    timeout = 120
    system_prompt = None

    def do_POST(self):
        if self.path != "/route":
            self.send_response(404)
            self.end_headers()
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw.decode("utf-8"))
            prompt = payload.get("prompt", "")
            messages = payload.get("messages")
            if not messages:
                messages = []
                if self.system_prompt:
                    messages.append({"role": "developer", "content": self.system_prompt})
                messages.append({"role": "user", "content": prompt})

            result = chat_completion(
                self.base_url,
                self.model,
                messages,
                self.tools,
                timeout=self.timeout,
                max_tokens=payload.get("max_tokens"),
                temperature=payload.get("temperature"),
                tool_choice=payload.get("tool_choice"),
            )
            choice = result.get("choices", [])[0]
            message = choice.get("message", {})

            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(message).encode("utf-8"))
        except Exception as exc:
            self.send_response(500)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(exc)}).encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=18010)
    parser.add_argument("--base-url", default="http://127.0.0.1:8000")
    parser.add_argument("--model", default="functiongemma-270m-it")
    parser.add_argument("--tools", default=r"C:\Users\david\PC_AI\Config\pcai-tools.json")
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--system-prompt", default=None)
    args = parser.parse_args()

    try:
        cfg = RouterConfig(
            host=args.host,
            port=args.port,
            base_url=args.base_url,
            model=args.model,
            tools=args.tools,
            timeout=args.timeout,
            system_prompt=args.system_prompt,
        )
    except ValidationError as exc:
        raise SystemExit(str(exc))

    RouterHandler.tools = load_tools(cfg.tools)
    RouterHandler.base_url = cfg.base_url
    RouterHandler.model = cfg.model
    RouterHandler.timeout = cfg.timeout
    if cfg.system_prompt and Path(cfg.system_prompt).exists():
        RouterHandler.system_prompt = Path(cfg.system_prompt).read_text(encoding="utf-8")

    server = ThreadingHTTPServer((cfg.host, cfg.port), RouterHandler)
    print(f"PC_AI Tool Router listening on http://{cfg.host}:{cfg.port}/route")
    server.serve_forever()


if __name__ == "__main__":
    main()
