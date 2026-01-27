#Requires -Version 5.1

<#
.EXAMPLE
    Get-PcaiServiceHealth
#>
function Get-PcaiServiceHealth {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Distribution = "Ubuntu",

        [Parameter()]
        [string]$OllamaBaseUrl = "http://localhost:11434",

        [Parameter()]
        [string]$vLLMBaseUrl = "http://localhost:8000"
    )

    $results = [PSCustomObject]@{
        Timestamp     = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        OverallStatus = 'Unknown'
        WSL           = @{ Status = 'Unknown'; Running = $false }
        Docker        = @{ Status = 'Unknown'; Running = $false }
        Ollama        = @{ Status = 'Unknown'; Responding = $false; Version = $null }
        vLLM          = @{ Status = 'Unknown'; Responding = $false }
        Bridges       = @{ Status = 'Unknown'; Count = 0 }
    }

    # 1. Check WSL
    try {
        $wslStatus = wsl -l -v | Select-String "$Distribution"
        if ($wslStatus -match "Running") {
            $results.WSL.Status = 'OK'
            $results.WSL.Running = $true
        } else {
            $results.WSL.Status = 'Stopped'
        }
    } catch {
        $results.WSL.Status = 'Error'
    }

    # 2. Check Docker
    try {
        $dockerProc = Get-Process -Name "Docker Desktop", "com.docker.backend" -ErrorAction SilentlyContinue
        if ($dockerProc) {
            $results.Docker.Running = $true
            # Check daemon
            $info = docker info --format '{{.ID}}' 2>$null
            if ($LASTEXITCODE -eq 0) {
                $results.Docker.Status = 'OK'
            } else {
                $results.Docker.Status = 'DaemonNotResponding'
            }
        } else {
            $results.Docker.Status = 'NotRunning'
        }
    } catch {
        $results.Docker.Status = 'Error'
    }

    # 3. Check Ollama
    try {
        $response = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/tags" -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($response) {
            $results.Ollama.Status = 'OK'
            $results.Ollama.Responding = $true
            # Optionally get version
            $ver = Invoke-RestMethod -Uri "$OllamaBaseUrl/api/version" -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
            $results.Ollama.Version = $ver.version
        } else {
            $results.Ollama.Status = 'NotResponding'
        }
    } catch {
        $results.Ollama.Status = 'Error'
    }

    # 4. Check vLLM (Optional)
    try {
        # vLLM usually has a /version or /health endpoint
        $vResponse = Invoke-RestMethod -Uri "$vLLMBaseUrl/v1/models" -Method Get -TimeoutSec 2 -ErrorAction SilentlyContinue
        if ($vResponse) {
            $results.vLLM.Status = 'OK'
            $results.vLLM.Responding = $true
        } else {
            $results.vLLM.Status = 'NotResponding'
        }
    } catch {
        $results.vLLM.Status = 'Error'
    }

    # 5. Check Bridges (socat processes in WSL)
    if ($results.WSL.Running) {
        try {
            $bridgeCount = wsl -d $Distribution -- pgrep -c socat 2>$null
            $results.Bridges.Count = [int]($bridgeCount.Trim() -as [int])
            $results.Bridges.Status = if ($results.Bridges.Count -gt 0) { 'OK' } else { 'None' }
        } catch {
            $results.Bridges.Status = 'Error'
        }
    }

    # Final Overall Status
    if ($results.WSL.Status -eq 'OK' -and $results.Ollama.Status -eq 'OK') {
        $results.OverallStatus = 'Healthy'
    } else {
        $results.OverallStatus = 'Degraded'
    }

    return $results
}
