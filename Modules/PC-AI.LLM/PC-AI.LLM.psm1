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
    OllamaPath = 'C:\Users\david\AppData\Local\Programs\Ollama\ollama.exe'
    OllamaApiUrl = 'http://localhost:11434'
    LMStudioApiUrl = 'http://localhost:1234'
    DefaultModel = 'qwen2.5-coder:7b'
    DefaultTimeout = 120
    ConfigPath = Join-Path -Path $ModuleRoot -ChildPath 'llm-config.json'
}

# Load configuration if exists
if (Test-Path -Path $script:ModuleConfig.ConfigPath) {
    try {
        $savedConfig = Get-Content -Path $script:ModuleConfig.ConfigPath -Raw | ConvertFrom-Json
        foreach ($key in $savedConfig.PSObject.Properties.Name) {
            if ($script:ModuleConfig.ContainsKey($key)) {
                $script:ModuleConfig[$key] = $savedConfig.$key
            }
        }
        Write-Verbose "Loaded configuration from $($script:ModuleConfig.ConfigPath)"
    }
    catch {
        Write-Warning "Failed to load configuration: $_"
    }
}

# Dot source private functions
if (Test-Path -Path $PrivatePath) {
    Get-ChildItem -Path $PrivatePath -Filter '*.ps1' -Recurse | ForEach-Object {
        try {
            . $_.FullName
            Write-Verbose "Loaded private function: $($_.Name)"
        }
        catch {
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
        }
        catch {
            Write-Error "Failed to load public function $($_.Name): $_"
        }
    }
}

# Export public functions
Export-ModuleMember -Function @(
    'Get-LLMStatus'
    'Send-OllamaRequest'
    'Invoke-LLMChat'
    'Invoke-PCDiagnosis'
    'Set-LLMConfig'
    'Invoke-SmartDiagnosis'
    'Invoke-NativeSearch'
)

Write-Verbose "PC-AI.LLM module loaded successfully"
