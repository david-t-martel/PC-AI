# PC-AI.LLM Quick Start Guide

Get started with PC-AI.LLM in under 5 minutes.

## Prerequisites Check

```powershell
# Verify Ollama is installed
Test-Path "C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe"
# Should return: True

# Check if Ollama is running
Test-NetConnection localhost -Port 11434 | Select-Object TcpTestSucceeded
# Should return: TcpTestSucceeded = True
```

If Ollama is not running, start it:
```powershell
Start-Process "C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe" -ArgumentList "serve"
```

## Step 1: Import Module

```powershell
Import-Module "C:\Users\david\PC_AI\Modules\PC-AI.LLM\PC-AI.LLM.psd1"
```

## Step 2: Verify Installation

```powershell
# Check status
Get-LLMStatus -TestConnection

# Should show:
# - Ollama Installed: True
# - API Connected: True
# - Models Available: 11
# - Default Model: qwen2.5-coder:7b
```

## Step 3: Try Your First Query

```powershell
$response = Send-OllamaRequest -Prompt "What are the most common causes of disk errors in Windows?"

Write-Host $response.Response
```

## Step 4: Analyze PC Diagnostics

### 4a. Run Hardware Diagnostics (Administrator Required)

```powershell
# Navigate to PC_AI directory
cd C:\Users\david\PC_AI

# Run diagnostics script
.\Get-PcDiagnostics.ps1

# This creates: Desktop\Hardware-Diagnostics-Report.txt
```

### 4b. Analyze with LLM

```powershell
Invoke-PCDiagnosis `
    -DiagnosticReportPath "$env:USERPROFILE\Desktop\Hardware-Diagnostics-Report.txt" `
    -SaveReport `
    -Verbose

# This creates: Desktop\PC-Diagnosis-Analysis.txt
```

## Step 5: Interactive Chat (Optional)

```powershell
Invoke-LLMChat -Interactive -System "You are a Windows system administrator expert"

# Chat commands:
# - Type messages to chat
# - 'exit' or 'quit' to end
# - 'clear' to reset history
# - 'history' to view conversation
```

## Common Commands

### Quick Health Check
```powershell
Get-LLMStatus
```

### Change Default Model
```powershell
# View available models
Get-LLMStatus | Select-Object -ExpandProperty Ollama | Select-Object -ExpandProperty Models | Format-Table Name, Size

# Set default model
Set-LLMConfig -DefaultModel "deepseek-r1:8b"
```

### View Configuration
```powershell
Set-LLMConfig -ShowConfig
```

### Get Help
```powershell
Get-Help Get-LLMStatus -Full
Get-Help Send-OllamaRequest -Examples
Get-Help Invoke-LLMChat -Detailed
Get-Help Invoke-PCDiagnosis -Full
Get-Help Set-LLMConfig -Examples
```

## Troubleshooting

### Problem: Module not found
```powershell
# Use full path
Import-Module "C:\Users\david\PC_AI\Modules\PC-AI.LLM\PC-AI.LLM.psd1" -Force
```

### Problem: Ollama connection failed
```powershell
# Check if Ollama is running
Get-Process ollama -ErrorAction SilentlyContinue

# If not running, start it
Start-Process "C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe" -ArgumentList "serve"

# Wait 5 seconds, then test again
Start-Sleep -Seconds 5
Get-LLMStatus -TestConnection
```

### Problem: Model not found
```powershell
# Pull the model
ollama pull qwen2.5-coder:7b

# Verify
Get-LLMStatus
```

### Problem: Request timeout
```powershell
# Increase timeout
Send-OllamaRequest -Prompt "..." -TimeoutSeconds 300

# Or set globally
Set-LLMConfig -DefaultTimeout 300
```

## Performance Tips

1. **First query is slower** - Model loads into memory (5-15 seconds)
2. **Subsequent queries are faster** - Model cached (1-5 seconds)
3. **Choose appropriate model**:
   - Fast: `mistral:latest`
   - Technical: `qwen2.5-coder:7b` (recommended)
   - Reasoning: `deepseek-r1:8b`
4. **Lower temperature for consistency** - Use 0.1-0.3 for diagnostic analysis
5. **Higher temperature for creativity** - Use 0.7-1.0 for general questions

## Next Steps

1. **Read full documentation**: See `README.md` for comprehensive guide
2. **Run examples**: Execute `.\USAGE_EXAMPLES.ps1` for working examples
3. **Analyze diagnostics**: Run `Get-PcDiagnostics.ps1` and analyze with LLM
4. **Explore models**: Try different models for different tasks
5. **Customize config**: Adjust settings with `Set-LLMConfig`

## Support

- **Module Help**: `Get-Help <FunctionName> -Full`
- **Examples**: `.\USAGE_EXAMPLES.ps1`
- **Documentation**: `README.md`
- **Implementation Details**: `MODULE_SUMMARY.md`

---

**You're now ready to use PC-AI.LLM!** 🚀

Start with `Get-LLMStatus -TestConnection` to verify everything is working.

