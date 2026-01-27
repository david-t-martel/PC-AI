#Requires -Version 5.1

function Get-LLMStatus {
    <#
    .SYNOPSIS
        Checks the status of Ollama LLM service and available models

    .DESCRIPTION
        Verifies Ollama installation, service status, API connectivity, and lists available models.
        Also checks LM Studio as a fallback option.

    .PARAMETER IncludeLMStudio
        Include LM Studio status check in the output

    .PARAMETER IncludeVLLM
        Include vLLM (OpenAI-compatible) status check in the output

    .PARAMETER TestConnection
        Perform connectivity tests to the API endpoints

    .EXAMPLE
        Get-LLMStatus
        Returns basic Ollama status and model list

    .EXAMPLE
        Get-LLMStatus -IncludeLMStudio -TestConnection
        Returns comprehensive status including LM Studio and connectivity tests

    .OUTPUTS
        PSCustomObject with status information
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [switch]$IncludeLMStudio,

        [Parameter()]
        [switch]$IncludeVLLM,

        [Parameter()]
        [switch]$TestConnection
    )

    begin {
        Write-Verbose 'Checking LLM service status...'
    }

    process {
        $status = [PSCustomObject]@{
            Timestamp       = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Ollama          = [PSCustomObject]@{
                Installed     = $false
                Path          = $script:ModuleConfig.OllamaPath
                ApiUrl        = $script:ModuleConfig.OllamaApiUrl
                ApiConnected  = $false
                ServiceStatus = $null
                Models        = @()
                DefaultModel  = $script:ModuleConfig.DefaultModel
            }
            VLLM            = $null
            LMStudio        = $null
            Recommendations = @()
        }

        # Test API connectivity first (supports Dockerized Ollama)
        $status.Ollama.ApiConnected = Test-OllamaConnection
        Write-Verbose "Ollama API connectivity: $($status.Ollama.ApiConnected)"

        # Check Ollama installation path (optional when Dockerized)
        if (Test-Path -Path $script:ModuleConfig.OllamaPath) {
            $status.Ollama.Installed = $true
            Write-Verbose "Ollama executable found at $($script:ModuleConfig.OllamaPath)"

            # Get Ollama service status (if exists)
            $serviceStatus = Get-ServiceStatus -ServiceName 'Ollama'
            $status.Ollama.ServiceStatus = $serviceStatus
        } elseif ($status.Ollama.ApiConnected) {
            # Ollama reachable via API (likely Dockerized or remote)
            $status.Ollama.Installed = $true
        }

        # Get available models if API is connected
        if ($status.Ollama.ApiConnected) {
            $models = Get-OllamaModels
            $status.Ollama.Models = @($models)

            Write-Verbose "Found $($models.Count) Ollama models"

            # Check if default model exists
            $defaultModelExists = $models | Where-Object { $_.Name -eq $script:ModuleConfig.DefaultModel }
            if (-not $defaultModelExists -and $models.Count -gt 0) {
                $status.Recommendations += "Default model '$($script:ModuleConfig.DefaultModel)' not found. Available models: $($models.Name -join ', ')"
            }
        } else {
            if (-not (Test-Path -Path $script:ModuleConfig.OllamaPath)) {
                $status.Recommendations += "Ollama executable not found at $($script:ModuleConfig.OllamaPath) and API is not reachable."
            }
            $status.Recommendations += 'Ollama API is not accessible. Ensure Ollama is running.'
        }

        # Check LM Studio if requested
        if ($IncludeLMStudio) {
            $status.LMStudio = [PSCustomObject]@{
                ApiUrl       = $script:ModuleConfig.LMStudioApiUrl
                ApiConnected = $false
            }

            if ($TestConnection -or $status.Ollama.ApiConnected -eq $false) {
                $status.LMStudio.ApiConnected = Test-LMStudioConnection
                Write-Verbose "LM Studio API connectivity: $($status.LMStudio.ApiConnected)"

                if ($status.LMStudio.ApiConnected -and -not $status.Ollama.ApiConnected) {
                    $status.Recommendations += 'LM Studio is available as a fallback option.'
                }
            }
        }

        # Check vLLM if requested
        if ($IncludeVLLM) {
            $status.VLLM = [PSCustomObject]@{
                ApiUrl       = $script:ModuleConfig.VLLMApiUrl
                ApiConnected = $false
                DefaultModel = $script:ModuleConfig.VLLMModel
                ModelInfo    = $null
                Metrics      = $null
            }

            if ($TestConnection -or $status.Ollama.ApiConnected -eq $false) {
                $status.VLLM.ApiConnected = Test-OpenAIConnection -ApiUrl $script:ModuleConfig.VLLMApiUrl
                Write-Verbose "vLLM API connectivity: $($status.VLLM.ApiConnected)"

                if ($status.VLLM.ApiConnected -and -not $status.Ollama.ApiConnected) {
                    $status.Recommendations += 'vLLM is available as a fallback option.'
                }

                if ($status.VLLM.ApiConnected) {
                    $status.VLLM.ModelInfo = Get-VLLMModelInfo -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel
                    $status.VLLM.Metrics = Get-VLLMMetricsSnapshot -ApiUrl $script:ModuleConfig.VLLMApiUrl -ModelName $script:ModuleConfig.VLLMModel
                }
            }
        }

        # Overall health check
        $modelCount = @($status.Ollama.Models).Count
        if ($status.Ollama.Installed -and $status.Ollama.ApiConnected -and $modelCount -gt 0) {
            Write-Verbose 'LLM system is healthy and ready'
        } else {
            Write-Warning 'LLM system is not fully operational. Check recommendations.'
        }

        return $status
    }

    end {
        Write-Verbose 'LLM status check complete'
    }
}
