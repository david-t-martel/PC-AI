import json
import subprocess
import sys
import time
from pathlib import Path

import pytest
import httpx


@pytest.mark.e2e
def test_tool_router_roundtrip(tmp_path, vllm_base_url: str, vllm_available: bool):
    if not vllm_available:
        pytest.skip("vLLM not reachable")

    router_script = Path(__file__).resolve().parents[1] / "tool_router.py"
    if not router_script.exists():
        pytest.skip("tool_router.py not found")

    port = 18011
    proc = subprocess.Popen(
        [sys.executable, str(router_script), "--port", str(port), "--base-url", vllm_base_url],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )

    try:
        time.sleep(1.5)
        resp = httpx.post(
            f"http://127.0.0.1:{port}/route",
            json={"prompt": "List available functions.", "max_tokens": 8, "temperature": 0.2},
            timeout=120,
        )
        assert resp.status_code == 200
        data = resp.json()
        assert "content" in data or "tool_calls" in data
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
