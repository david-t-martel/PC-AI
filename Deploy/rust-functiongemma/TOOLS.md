# FunctionGemma Tool Catalog

Source: `Config/pcai-tools.json`

## Tools

### SearchDocs
Search vendor documentation for error codes and device guidance.

Parameters:
- query (string, required)
- source (string, optional) enum=Microsoft, Intel, AMD, Dell, HP, Lenovo, Generic

### GetSystemInfo
Query system diagnostics for storage, network, USB, BIOS, or OS details.

Parameters:
- category (string, required) enum=Storage, Network, USB, BIOS, OS
- detail (string, optional)

### SearchLogs
Search local log files for a regex pattern (native-first).

Parameters:
- pattern (string, required)
- rootPath (string, optional)
- filePattern (string, optional)
- caseSensitive (boolean, optional)
- contextLines (integer, optional)
- maxMatches (integer, optional)

### pcai_run_wsl_network_tool
Run the WSL network toolkit with a mode: check, diagnose, repair, full.

Parameters:
- mode (string, required) enum=check, diagnose, repair, full

### pcai_get_wsl_health
Collect WSL and Docker environment health summary.

Parameters:

### pcai_optimize_model_host
Tune WSL and GPU resources for performance/safety.

Parameters:
- gpu_limit (number, optional)

### pcai_restart_wsl
Restart WSL to reinitialize networking and services.

Parameters:

### pcai_get_docker_status
Return Docker Desktop health and runtime status.

Parameters:

### pcai_set_provider_order
Update LLM provider fallback order (comma-separated list).

Parameters:
- order (string, required)

### pcai_start_service
Start a PC_AI service (e.g., PC_AI-VLLM, PC_AI-HVSockProxy).

Parameters:
- service (string, required)

### pcai_stop_service
Stop a PC_AI service (e.g., PC_AI-VLLM, PC_AI-HVSockProxy).

Parameters:
- service (string, required)

### pcai_restart_service
Restart a PC_AI service.

Parameters:
- service (string, required)

## Negative examples (NO_TOOL)
- Hello, how are you today?
- What is the capital of France?
- Tell me a joke.
- How do I cook pasta?
- Write a poem about the sea.

## Notes
- Negative examples map to `NO_TOOL` responses.
- Keep this file in sync with `Deploy/rust-functiongemma-train/src/schema_utils.rs`.
