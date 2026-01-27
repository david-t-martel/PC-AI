import shutil
import subprocess

import pytest


@pytest.mark.functional
def test_pcai_get_llm_status():
    pwsh = shutil.which("pwsh")
    if not pwsh:
        pytest.skip("pwsh not available")

    cmd = [
        pwsh,
        "-NoProfile",
        "-Command",
        "Import-Module C:\\Users\\david\\PC_AI\\Modules\\PC-AI.LLM; Get-LLMStatus -IncludeVLLM -TestConnection | ConvertTo-Json -Depth 6",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    assert result.returncode == 0
    assert "Ollama" in result.stdout
