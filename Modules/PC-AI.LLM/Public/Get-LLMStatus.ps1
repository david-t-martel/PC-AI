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
        [switch]$TestConnection
    )

    begin {
        Write-Verbose "Checking LLM service status..."
    }

    process {
        $status = [PSCustomObject]@{
            Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
            Ollama = [PSCustomObject]@{
                Installed = $false
                Path = $script:ModuleConfig.OllamaPath
                ApiUrl = $script:ModuleConfig.OllamaApiUrl
                ApiConnected = $false
                ServiceStatus = $null
                Models = @()
                DefaultModel = $script:ModuleConfig.DefaultModel
            }
            LMStudio = $null
            Recommendations = @()
        }

        # Check Ollama installation
        if (Test-Path -Path $script:ModuleConfig.OllamaPath) {
            $status.Ollama.Installed = $true
            Write-Verbose "Ollama executable found at $($script:ModuleConfig.OllamaPath)"

            # Get Ollama service status (if exists)
            $serviceStatus = Get-ServiceStatus -ServiceName 'Ollama'
            $status.Ollama.ServiceStatus = $serviceStatus

            # Test API connectivity
            # Always test API since Ollama can run as a process without a Windows service
            $status.Ollama.ApiConnected = Test-OllamaConnection
            Write-Verbose "Ollama API connectivity: $($status.Ollama.ApiConnected)"

            # Get available models if API is connected
            if ($status.Ollama.ApiConnected) {
                $models = Get-OllamaModels
                $status.Ollama.Models = $models

                Write-Verbose "Found $($models.Count) Ollama models"

                # Check if default model exists
                $defaultModelExists = $models | Where-Object { $_.Name -eq $script:ModuleConfig.DefaultModel }
                if (-not $defaultModelExists -and $models.Count -gt 0) {
                    $status.Recommendations += "Default model '$($script:ModuleConfig.DefaultModel)' not found. Available models: $($models.Name -join ', ')"
                }
            }
            else {
                $status.Recommendations += "Ollama API is not accessible. Ensure Ollama is running."
            }
        }
        else {
            $status.Recommendations += "Ollama executable not found at $($script:ModuleConfig.OllamaPath). Install Ollama from https://ollama.ai"
        }

        # Check LM Studio if requested
        if ($IncludeLMStudio) {
            $status.LMStudio = [PSCustomObject]@{
                ApiUrl = $script:ModuleConfig.LMStudioApiUrl
                ApiConnected = $false
            }

            if ($TestConnection -or $status.Ollama.ApiConnected -eq $false) {
                $status.LMStudio.ApiConnected = Test-LMStudioConnection
                Write-Verbose "LM Studio API connectivity: $($status.LMStudio.ApiConnected)"

                if ($status.LMStudio.ApiConnected -and -not $status.Ollama.ApiConnected) {
                    $status.Recommendations += "LM Studio is available as a fallback option."
                }
            }
        }

        # Overall health check
        if ($status.Ollama.Installed -and $status.Ollama.ApiConnected -and $status.Ollama.Models.Count -gt 0) {
            Write-Verbose "LLM system is healthy and ready"
        }
        else {
            Write-Warning "LLM system is not fully operational. Check recommendations."
        }

        return $status
    }

    end {
        Write-Verbose "LLM status check complete"
    }
}
