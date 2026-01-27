#Requires -Version 5.1

<#
.SYNOPSIS
    PC-AI.LLM PowerShell Module Loader
.DESCRIPTION
    Loads the PC-AI.LLM module for Ollama integration with PC diagnostics
#>

# Get module paths
$ModuleRoot = $PSScriptRoot
$PrivatePath = Join-Path -Path $ModuleRoot -ChildPath 'Private'
$PublicPath = Join-Path -Path $ModuleRoot -ChildPath 'Public'

# Module-level variables
$script:ModuleConfig = @{
    OllamaPath     = 'C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe'
    OllamaApiUrl   = 'http://127.0.0.1:11434'
    LMStudioApiUrl = 'http://localhost:1234'
    VLLMApiUrl     = 'http://127.0.0.1:8000'
    VLLMModel      = 'functiongemma-270m-it'
    DefaultModel   = 'qwen2.5-coder:7b'
    DefaultTimeout = 120
    ProviderOrder  = @('ollama','vllm','lmstudio')
    ConfigPath     = Join-Path -Path $ModuleRoot -ChildPath 'llm-config.json'
}

# Load configuration if exists (module config)
if (Test-Path -Path $script:ModuleConfig.ConfigPath) {
    try {
        $savedConfig = Get-Content -Path $script:ModuleConfig.ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in $savedConfig.PSObject.Properties.Name) {
            if ($script:ModuleConfig.ContainsKey($key)) {
                $script:ModuleConfig[$key] = $savedConfig.$key
            }
        }
        Write-Verbose "Loaded configuration from $($script:ModuleConfig.ConfigPath)"
    } catch {
        Write-Warning "Failed to load module configuration: $_"
    }
}

# Prefer project-level config if present (PC_AI\Config\llm-config.json)
$projectRoot = Split-Path -Parent (Split-Path -Parent $ModuleRoot)
$projectConfigPath = Join-Path -Path $projectRoot -ChildPath 'Config\llm-config.json'
if (Test-Path -Path $projectConfigPath) {
    try {
        $projectConfig = Get-Content -Path $projectConfigPath -Raw | ConvertFrom-Json
        if ($projectConfig.providers.ollama.baseUrl) {
            $script:ModuleConfig.OllamaApiUrl = $projectConfig.providers.ollama.baseUrl
        }
        if ($projectConfig.providers.ollama.defaultModel) {
            $script:ModuleConfig.DefaultModel = $projectConfig.providers.ollama.defaultModel
        }
        if ($projectConfig.providers.ollama.timeout) {
            $script:ModuleConfig.DefaultTimeout = [math]::Ceiling($projectConfig.providers.ollama.timeout / 1000)
        }
        if ($projectConfig.providers.lmstudio.baseUrl) {
            $script:ModuleConfig.LMStudioApiUrl = $projectConfig.providers.lmstudio.baseUrl
        }
        if ($projectConfig.providers.vllm.baseUrl) {
            $script:ModuleConfig.VLLMApiUrl = $projectConfig.providers.vllm.baseUrl
        }
        if ($projectConfig.providers.vllm.defaultModel) {
            $script:ModuleConfig.VLLMModel = $projectConfig.providers.vllm.defaultModel
        }
        if ($projectConfig.fallbackOrder) {
            $script:ModuleConfig.ProviderOrder = @($projectConfig.fallbackOrder)
        }
        $script:ModuleConfig.ProjectConfigPath = $projectConfigPath
        Write-Verbose "Loaded project configuration from $projectConfigPath"
    } catch {
        Write-Warning "Failed to load project configuration: $_"
    }
}

# Dot source private functions
if (Test-Path -Path $PrivatePath) {
    Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded private function: $($_.Name)"
        } catch {
            Write-Error "Failed to load private function $($_.Name): $_"
        }
    }
}

# Dot source public functions
if (Test-Path -Path $PublicPath) {
    Get-ChildItem -Path $PublicPath -Filter '*.ps1' -Recurse | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded public function: $($_.Name)"
        } catch {
            Write-Error "Failed to load public function $($_.Name): $_"
        }
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-LLMStatus'
    'Send-OllamaRequest'
    'Invoke-LLMChat'
    'Invoke-LLMChatTui'
    'Invoke-FunctionGemmaReAct'
    'Invoke-PCDiagnosis'
    'Set-LLMConfig'
    'Set-LLMProviderOrder'
    'Invoke-SmartDiagnosis'
    'Invoke-NativeSearch'
)

Write-Verbose 'PC-AI.LLM module loaded successfully'
