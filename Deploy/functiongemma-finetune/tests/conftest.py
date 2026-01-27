import os
import socket

import pytest


def is_port_open(host: str, port: int, timeout: float = 0.5) -> bool:
    try:
        with socket.create_connection((host, port), timeout=timeout):
            return True
    except OSError:
        return False


@pytest.fixture(scope="session")
def vllm_base_url() -> str:
    return os.environ.get("VLLM_BASE_URL", "http://127.0.0.1:8000")


@pytest.fixture(scope="session")
def vllm_available(vllm_base_url: str) -> bool:
    host = vllm_base_url.replace("http://", "").replace("https://", "").split(":")[0]
    port = int(vllm_base_url.rsplit(":", 1)[-1])
    return is_port_open(host, port)


@pytest.fixture(scope="session")
def tool_config_path() -> str:
    return os.environ.get(
        "PCAI_TOOL_CONFIG",
        r"C:\Users\david\PC_AI\Config\pcai-tools.json",
    )
