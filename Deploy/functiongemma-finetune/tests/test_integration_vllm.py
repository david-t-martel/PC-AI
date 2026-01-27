import json

import pytest
import httpx


@pytest.mark.integration
def test_vllm_health(vllm_base_url: str, vllm_available: bool):
    if not vllm_available:
        pytest.skip("vLLM not reachable")

    resp = httpx.get(f"{vllm_base_url}/health", timeout=10)
    assert resp.status_code == 200


@pytest.mark.integration
def test_vllm_models(vllm_base_url: str, vllm_available: bool):
    if not vllm_available:
        pytest.skip("vLLM not reachable")

    resp = httpx.get(f"{vllm_base_url}/v1/models", timeout=10)
    assert resp.status_code == 200
    payload = resp.json()
    assert "data" in payload
    assert len(payload["data"]) > 0
