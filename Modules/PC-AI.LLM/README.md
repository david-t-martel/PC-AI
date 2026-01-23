# PC-AI.LLM PowerShell Module

PowerShell module for integrating **Ollama** local LLM with PC diagnostics and system analysis.

## Overview

PC-AI.LLM provides a complete PowerShell interface to Ollama, enabling intelligent analysis of PC hardware diagnostics, interactive chat sessions, and automated AI-powered troubleshooting.

## Features

- **Full Ollama API Integration** - Native PowerShell wrappers for Ollama generate and chat endpoints
- **PC Diagnostics Analysis** - Automated analysis of hardware diagnostic reports using LLM reasoning
- **Interactive Chat** - Conversational interface with conversation history management
- **Model Management** - Easy model selection, status checking, and configuration
- **Error Handling** - Robust retry logic, timeout handling, and connection fallback
- **LM Studio Support** - Fallback to LM Studio API when Ollama is unavailable

## Installation

### Prerequisites

1. **Ollama** installed at `C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe`
2. **Models pulled** (recommended: `qwen2.5-coder:7b` for technical analysis)

```powershell
# Pull recommended model
ollama pull qwen2.5-coder:7b
```

### Module Installation

```powershell
# Import module
Import-Module "C:\Users\david\PC_AI\Modules\PC-AI.LLM\PC-AI.LLM.psd1"

# Verify installation
Get-Command -Module PC-AI.LLM
```

## Quick Start

### 1. Check LLM Status

```powershell
Get-LLMStatus -TestConnection

# Output shows:
# - Ollama installation status
# - API connectivity
# - Available models
# - Default model
```

### 2. Send Simple Request

```powershell
$response = Send-OllamaRequest -Prompt "What causes disk errors in Windows?"

Write-Host $response.Response
```

### 3. Analyze Diagnostic Report

```powershell
# First, run hardware diagnostics
.\Get-PcDiagnostics.ps1

# Then analyze with LLM
Invoke-PCDiagnosis -DiagnosticReportPath "$env:USERPROFILE\Desktop\Hardware-Diagnostics-Report.txt" -SaveReport
```

### 4. Interactive Chat

```powershell
Invoke-LLMChat -Interactive -Model "qwen2.5-coder:7b" -System "You are a Windows system administrator expert"

# Commands in chat:
# - Type messages to chat
# - 'exit', 'quit', 'q' to end session
# - 'clear' to reset history
# - 'history' to view conversation
```

## Functions

### Get-LLMStatus

Check Ollama installation, API connectivity, and available models.

```powershell
Get-LLMStatus -TestConnection -IncludeLMStudio
```

**Parameters:**
- `-TestConnection` - Test API connectivity
- `-IncludeLMStudio` - Check LM Studio availability

**Output:**
- Ollama installation status
- API connection status
- Available models list
- Service status
- Recommendations

### Send-OllamaRequest

Send text generation request to Ollama.

```powershell
Send-OllamaRequest -Prompt "Explain RAID" -Model "qwen2.5-coder:7b" -Temperature 0.7
```

**Parameters:**
- `-Prompt` (required) - Text prompt
- `-Model` - Model name (default: qwen2.5-coder:7b)
- `-System` - System prompt
- `-Temperature` - Randomness (0.0-2.0, default: 0.7)
- `-MaxTokens` - Maximum tokens to generate
- `-Stream` - Enable streaming output
- `-TimeoutSeconds` - Request timeout (default: 120)
- `-MaxRetries` - Retry attempts (default: 3)

**Output:**
- Response text
- Timing metrics
- Token statistics
- Tokens per second

### Invoke-LLMChat

Interactive or single-shot chat interface.

```powershell
# Single message
$result = Invoke-LLMChat -Message "What is PowerShell?" -System "You are a helpful assistant"

# Interactive mode
Invoke-LLMChat -Interactive -Model "deepseek-r1:8b"
```

**Parameters:**
- `-Message` - User message (required in non-interactive mode)
- `-Model` - Model name
- `-System` - System prompt
- `-Temperature` - Randomness (0.0-2.0)
- `-MaxTokens` - Max tokens per response
- `-Interactive` - Start interactive session
- `-History` - Existing conversation history

**Interactive Commands:**
- `exit`, `quit`, `q` - End session
- `clear` - Reset conversation history
- `history` - View conversation

**Output:**
- Response text
- Conversation history
- Message count
- Timing metrics

### Invoke-PCDiagnosis

Analyze PC diagnostic reports using LLM.

```powershell
Invoke-PCDiagnosis -DiagnosticReportPath "report.txt" -SaveReport -Model "qwen2.5-coder:7b"
```

**Parameters:**
- `-DiagnosticReportPath` - Path to diagnostic report file
- `-ReportText` - Direct report text input
- `-Model` - Model for analysis (default: qwen2.5-coder:7b)
- `-Temperature` - Analysis consistency (default: 0.3 for deterministic)
- `-IncludeRawResponse` - Include raw API response
- `-SaveReport` - Save analysis to file
- `-OutputPath` - Custom output path (default: Desktop\PC-Diagnosis-Analysis.txt)

**Features:**
- Loads `DIAGNOSE.md` as system prompt
- Loads `DIAGNOSE_LOGIC.md` as reasoning framework
- Structured analysis output:
  - Summary (key findings)
  - Findings by category
  - Priority issues (Critical/High/Medium/Low)
  - Recommended next steps

**Output:**
- Structured analysis
- Model and timing information
- Token statistics
- Optional: Report saved to file

### Set-LLMConfig

Configure module settings.

```powershell
# View current config
Set-LLMConfig -ShowConfig

# Change default model
Set-LLMConfig -DefaultModel "deepseek-r1:8b"

# Set timeout
Set-LLMConfig -DefaultTimeout 180

# Reset to defaults
Set-LLMConfig -Reset
```

**Parameters:**
- `-DefaultModel` - Set default model
- `-OllamaApiUrl` - Ollama API endpoint
- `-LMStudioApiUrl` - LM Studio API endpoint
- `-OllamaPath` - Path to Ollama executable
- `-DefaultTimeout` - Default timeout (seconds)
- `-ShowConfig` - Display current config
- `-Reset` - Reset to defaults

**Configuration saved to:** `llm-config.json` in module directory

## Model Selection Guide

### Recommended Models

| Model | Size | Use Case | Speed | Quality |
|-------|------|----------|-------|---------|
| **qwen2.5-coder:7b** | 4.7GB | Technical analysis, diagnostics | Fast | High |
| **deepseek-r1:8b** | 5.2GB | Complex reasoning, root cause | Medium | Very High |
| **mistral:7b** | 4.4GB | General chat, fast responses | Fast | Good |
| **gemma3:12b** | 8.1GB | High quality, detailed analysis | Slower | Excellent |
| **nomic-embed-text** | 274MB | Text embeddings only | N/A | N/A |

### How to Choose

- **PC Diagnostics**: `qwen2.5-coder:7b` (optimized for technical content)
- **Complex Issues**: `deepseek-r1:8b` (better reasoning chains)
- **Quick Answers**: `mistral:7b` (fastest general model)
- **Detailed Analysis**: `gemma3:12b` (highest quality, slower)

### Pull New Models

```powershell
# From command line
ollama pull modelname:tag

# Verify in module
Get-LLMStatus
```

## Configuration

Module uses `llm-config.json` for persistence:

```json
{
  "OllamaPath": "C:\\Users\\david\\AppData\\Local\\Programs\\Ollama\\ollama.exe",
  "OllamaApiUrl": "http://localhost:11434",
  "LMStudioApiUrl": "http://localhost:1234",
  "DefaultModel": "qwen2.5-coder:7b",
  "DefaultTimeout": 120
}
```

## PC Diagnostics Workflow

### Complete Diagnostic Analysis

```powershell
# Step 1: Run hardware diagnostics (as Administrator)
.\Get-PcDiagnostics.ps1

# Step 2: Load module
Import-Module "C:\Users\david\PC_AI\Modules\PC-AI.LLM\PC-AI.LLM.psd1"

# Step 3: Check LLM status
Get-LLMStatus -TestConnection

# Step 4: Analyze report
$analysis = Invoke-PCDiagnosis `
    -DiagnosticReportPath "$env:USERPROFILE\Desktop\Hardware-Diagnostics-Report.txt" `
    -Model "qwen2.5-coder:7b" `
    -SaveReport `
    -Verbose

# Step 5: Review analysis
Get-Content "$env:USERPROFILE\Desktop\PC-Diagnosis-Analysis.txt"
```

### Expected Analysis Output

```
PC DIAGNOSTICS ANALYSIS REPORT
Generated: 2026-01-23 02:30:00
Model: qwen2.5-coder:7b

================================================================================

## Summary
- No critical hardware failures detected
- 2 USB devices with minor errors (error code 28 - drivers not installed)
- Disk health is good (SMART status: OK)
- Network adapters functioning normally

## Findings by Category

### Devices with Errors
- USB Mass Storage Device (Error 28): Missing drivers
- Unknown Device (Error 1): Configuration issue

### Disk Health
- All disks report SMART status: OK
- No bad sectors or reallocated sectors detected

[... detailed analysis ...]

## Priority Issues
- High: Install missing USB drivers
- Medium: Investigate unknown device configuration

## Recommended Next Steps
1. Run Windows Update to install missing USB drivers
2. Check Device Manager for unknown devices
3. Monitor disk health with CrystalDiskInfo
```

## Troubleshooting

### Ollama Not Running

```powershell
# Check if Ollama is installed
Get-LLMStatus

# If installed but not running, start Ollama manually
& "C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe" serve
```

### Model Not Found

```powershell
# List available models
Get-LLMStatus

# Pull missing model
ollama pull qwen2.5-coder:7b

# Verify
Get-LLMStatus
```

### Connection Timeout

```powershell
# Increase timeout
Send-OllamaRequest -Prompt "test" -TimeoutSeconds 300

# Or set globally
Set-LLMConfig -DefaultTimeout 300
```

### API Connection Failed

```powershell
# Test connectivity
Test-NetConnection localhost -Port 11434

# Check if Ollama service is running
Get-Process ollama -ErrorAction SilentlyContinue

# Check LM Studio as fallback
Get-LLMStatus -IncludeLMStudio
```

## Advanced Usage

### Streaming Responses

```powershell
Send-OllamaRequest -Prompt "Explain RAID" -Stream
```

### Custom System Prompts

```powershell
$systemPrompt = @"
You are a Windows system administrator with 20 years of experience.
Focus on practical solutions and safety-first recommendations.
Be concise and technical.
"@

Send-OllamaRequest -Prompt "How to fix disk errors?" -System $systemPrompt
```

### Conversation Context

```powershell
# First message
$chat1 = Invoke-LLMChat -Message "What is SMART?"

# Continue conversation
$chat2 = Invoke-LLMChat -Message "How do I check it?" -History $chat1.History

# View full conversation
$chat2.History | ForEach-Object {
    Write-Host "[$($_.role)]: $($_.content)"
}
```

### Batch Analysis

```powershell
# Analyze multiple reports
$reports = Get-ChildItem "C:\Diagnostics\*.txt"

foreach ($report in $reports) {
    Write-Host "Analyzing $($report.Name)..."
    Invoke-PCDiagnosis -DiagnosticReportPath $report.FullName -SaveReport
}
```

## Performance Tips

1. **Use appropriate models**:
   - Fast queries: `mistral:7b`
   - Technical analysis: `qwen2.5-coder:7b`
   - Complex reasoning: `deepseek-r1:8b`

2. **Adjust temperature**:
   - Consistent results: `0.1-0.3`
   - Balanced: `0.7` (default)
   - Creative: `1.0-2.0`

3. **Optimize timeouts**:
   - Short queries: 30-60 seconds
   - Long analysis: 120-300 seconds

4. **Keep models loaded**:
   - First request is slower (model loading)
   - Subsequent requests are faster (model cached in memory)

## Examples

See `USAGE_EXAMPLES.ps1` for comprehensive examples of all functions.

```powershell
# Run examples
.\USAGE_EXAMPLES.ps1
```

## API Reference

All functions support:
- Comment-based help (`Get-Help FunctionName -Full`)
- Pipeline input where appropriate
- Verbose logging (`-Verbose`)
- Error handling with retries

## Integration Points

### DIAGNOSE.md
System prompt defining LLM assistant behavior, safety constraints, and workflow for PC diagnostics.

### DIAGNOSE_LOGIC.md
Branched reasoning decision tree for analyzing diagnostic output with structured severity classification.

### Get-PcDiagnostics.ps1
Hardware diagnostics script that generates reports analyzed by `Invoke-PCDiagnosis`.

## Version History

### 1.0.0 (2026-01-23)
- Initial release
- Full Ollama API integration
- PC diagnostics analysis
- Interactive chat
- Configuration management
- LM Studio fallback support

## License

Part of the PC-AI project.

## Support

For issues or questions:
1. Check `Get-Help <FunctionName> -Full`
2. Run `USAGE_EXAMPLES.ps1` for working examples
3. Verify Ollama status with `Get-LLMStatus -TestConnection`
