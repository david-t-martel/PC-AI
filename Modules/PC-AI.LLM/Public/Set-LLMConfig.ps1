#Requires -Version 5.1

function Set-LLMConfig {
    <#
    .SYNOPSIS
        Configures LLM module settings

    .DESCRIPTION
        Sets and persists configuration for the PC-AI.LLM module including default model,
        API endpoints, timeouts, and other operational parameters.

    .PARAMETER DefaultModel
        Default model to use for LLM requests

    .PARAMETER OllamaApiUrl
        Ollama API endpoint URL

    .PARAMETER LMStudioApiUrl
        LM Studio API endpoint URL

    .PARAMETER OllamaPath
        Path to Ollama executable

    .PARAMETER DefaultTimeout
        Default timeout in seconds for API requests

    .PARAMETER ShowConfig
        Display current configuration without making changes

    .PARAMETER Reset
        Reset configuration to default values

    .EXAMPLE
        Set-LLMConfig -DefaultModel "deepseek-r1:8b"
        Changes the default model

    .EXAMPLE
        Set-LLMConfig -DefaultTimeout 180
        Sets default timeout to 3 minutes

    .EXAMPLE
        Set-LLMConfig -ShowConfig
        Displays current configuration

    .EXAMPLE
        Set-LLMConfig -Reset
        Resets all settings to defaults

    .OUTPUTS
        PSCustomObject with current configuration
    #>
    [CmdletBinding(DefaultParameterSetName = 'SetConfig')]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(ParameterSetName = 'SetConfig')]
        [string]$DefaultModel,

        [Parameter(ParameterSetName = 'SetConfig')]
        [ValidatePattern('^https?://')]
        [string]$OllamaApiUrl,

        [Parameter(ParameterSetName = 'SetConfig')]
        [ValidatePattern('^https?://')]
        [string]$LMStudioApiUrl,

        [Parameter(ParameterSetName = 'SetConfig')]
        [ValidateScript({ Test-Path $_ -PathType Leaf })]
        [string]$OllamaPath,

        [Parameter(ParameterSetName = 'SetConfig')]
        [ValidateRange(1, 600)]
        [int]$DefaultTimeout,

        [Parameter(ParameterSetName = 'ShowConfig')]
        [switch]$ShowConfig,

        [Parameter(ParameterSetName = 'Reset')]
        [switch]$Reset
    )

    begin {
        Write-Verbose "Configuring LLM module settings..."

        $configPath = $script:ModuleConfig.ConfigPath
        $projectConfigPath = $script:ModuleConfig.ProjectConfigPath

        # Default configuration
        $defaultConfig = @{
            OllamaPath = 'C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe'
            OllamaApiUrl = 'http://localhost:11434'
            LMStudioApiUrl = 'http://localhost:1234'
            DefaultModel = 'qwen2.5-coder:7b'
            DefaultTimeout = 120
        }
    }

    process {
        if ($Reset) {
            Write-Host "Resetting configuration to defaults..." -ForegroundColor Yellow

            # Reset to defaults
            foreach ($key in $defaultConfig.Keys) {
                $script:ModuleConfig[$key] = $defaultConfig[$key]
            }

            # Save to file
            try {
                $jsonContent = $script:ModuleConfig | ConvertTo-Json -Depth 10
                [System.IO.File]::WriteAllText($configPath, $jsonContent, [System.Text.Encoding]::UTF8)
                Write-Host "Configuration reset successfully" -ForegroundColor Green
            }
            catch {
                Write-Error "Failed to save configuration: $_"
            }
        }
        elseif ($ShowConfig) {
            # Display current configuration
            Write-Host "`nCurrent LLM Configuration:" -ForegroundColor Cyan
            Write-Host ("=" * 60) -ForegroundColor Gray

            foreach ($key in $script:ModuleConfig.Keys | Sort-Object) {
                $value = $script:ModuleConfig[$key]
                Write-Host "$($key.PadRight(20)): " -NoNewline -ForegroundColor Yellow
                Write-Host $value -ForegroundColor White
            }

            Write-Host ("=" * 60) -ForegroundColor Gray
        }
        else {
            # Update configuration
            $updated = $false

            if ($PSBoundParameters.ContainsKey('DefaultModel')) {
                # Verify model exists if Ollama is available
                if (Test-OllamaConnection) {
                    $availableModels = Get-OllamaModels
                    $modelExists = $availableModels | Where-Object { $_.Name -eq $DefaultModel }

                    if (-not $modelExists) {
                        Write-Warning "Model '$DefaultModel' not found in Ollama. Available models: $($availableModels.Name -join ', ')"
                        Write-Host "You may need to pull the model with: ollama pull $DefaultModel" -ForegroundColor Yellow
                    }
                }

                $script:ModuleConfig.DefaultModel = $DefaultModel
                Write-Host "Default model set to: $DefaultModel" -ForegroundColor Green
                $updated = $true
            }

            if ($PSBoundParameters.ContainsKey('OllamaApiUrl')) {
                $script:ModuleConfig.OllamaApiUrl = $OllamaApiUrl
                Write-Host "Ollama API URL set to: $OllamaApiUrl" -ForegroundColor Green
                $updated = $true
            }

            if ($PSBoundParameters.ContainsKey('LMStudioApiUrl')) {
                $script:ModuleConfig.LMStudioApiUrl = $LMStudioApiUrl
                Write-Host "LM Studio API URL set to: $LMStudioApiUrl" -ForegroundColor Green
                $updated = $true
            }

            if ($PSBoundParameters.ContainsKey('OllamaPath')) {
                $script:ModuleConfig.OllamaPath = $OllamaPath
                Write-Host "Ollama path set to: $OllamaPath" -ForegroundColor Green
                $updated = $true
            }

            if ($PSBoundParameters.ContainsKey('DefaultTimeout')) {
                $script:ModuleConfig.DefaultTimeout = $DefaultTimeout
                Write-Host "Default timeout set to: $DefaultTimeout seconds" -ForegroundColor Green
                $updated = $true
            }

            # Save configuration if anything was updated
            if ($updated) {
                try {
                    $jsonContent = $script:ModuleConfig | ConvertTo-Json -Depth 10
                    [System.IO.File]::WriteAllText($configPath, $jsonContent, [System.Text.Encoding]::UTF8)
                    Write-Verbose "Configuration saved to: $configPath"
                }
                catch {
                    Write-Error "Failed to save configuration: $_"
                }

                # Also update project-level config if available
                if ($projectConfigPath -and (Test-Path $projectConfigPath)) {
                    try {
                        $projectConfig = Get-Content -Path $projectConfigPath -Raw | ConvertFrom-Json
                        if ($PSBoundParameters.ContainsKey('DefaultModel')) {
                            $projectConfig.providers.ollama.defaultModel = $DefaultModel
                        }
                        if ($PSBoundParameters.ContainsKey('OllamaApiUrl')) {
                            $projectConfig.providers.ollama.baseUrl = $OllamaApiUrl
                        }
                        if ($PSBoundParameters.ContainsKey('LMStudioApiUrl')) {
                            $projectConfig.providers.lmstudio.baseUrl = $LMStudioApiUrl
                        }
                        if ($PSBoundParameters.ContainsKey('DefaultTimeout')) {
                            $projectConfig.providers.ollama.timeout = ($DefaultTimeout * 1000)
                        }

                        $projectJson = $projectConfig | ConvertTo-Json -Depth 10
                        [System.IO.File]::WriteAllText($projectConfigPath, $projectJson, [System.Text.Encoding]::UTF8)
                        Write-Verbose "Project configuration saved to: $projectConfigPath"
                    }
                    catch {
                        Write-Warning "Failed to update project configuration: $_"
                    }
                }
            }
            else {
                Write-Warning "No configuration changes specified. Use -ShowConfig to view current settings."
            }
        }

        # Return current configuration
        return [PSCustomObject]@{
            OllamaPath = $script:ModuleConfig.OllamaPath
            OllamaApiUrl = $script:ModuleConfig.OllamaApiUrl
            LMStudioApiUrl = $script:ModuleConfig.LMStudioApiUrl
            DefaultModel = $script:ModuleConfig.DefaultModel
            DefaultTimeout = $script:ModuleConfig.DefaultTimeout
            ConfigPath = $configPath
            LastUpdated = Get-Date
        }
    }

    end {
        Write-Verbose "LLM configuration completed"
    }
}

