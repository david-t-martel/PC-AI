<#
.SYNOPSIS
    Integration tests for routed chat provider selection (Ollama/vLLM).
#>

BeforeAll {
    $script:PcaiRoot = Join-Path $PSScriptRoot '..\..'
    $script:ModulePath = Join-Path $script:PcaiRoot 'Modules\PC-AI.LLM\PC-AI.LLM.psd1'
    Import-Module $script:ModulePath -Force -ErrorAction Stop
}

Describe "Invoke-LLMChatRouted provider selection" -Tag 'Integration', 'Router', 'Provider' {
    BeforeEach {
        Mock Invoke-FunctionGemmaReAct {
            [PSCustomObject]@{ ToolCalls = @(); ToolResults = @() }
        } -ModuleName PC-AI.LLM
    }

    It "Should route to Ollama when available" {
        Mock Test-OllamaConnection { $true } -ModuleName PC-AI.LLM
        Mock Test-OpenAIConnection { $false } -ModuleName PC-AI.LLM
        Mock Invoke-OllamaChat {
            [PSCustomObject]@{ message = @{ content = 'ollama response' } }
        } -ModuleName PC-AI.LLM

        $result = Invoke-LLMChatRouted -Message "Hi" -Mode chat -Provider auto
        $result.Provider | Should -Be 'ollama'
        $result.Response | Should -Be 'ollama response'
    }

    It "Should route to vLLM when Ollama is unavailable" {
        Mock Test-OllamaConnection { $false } -ModuleName PC-AI.LLM
        Mock Test-OpenAIConnection { $true } -ModuleName PC-AI.LLM
        Mock Invoke-OpenAIChat {
            [PSCustomObject]@{ message = @{ content = 'vllm response' } }
        } -ModuleName PC-AI.LLM

        $result = Invoke-LLMChatRouted -Message "Hi" -Mode chat -Provider auto
        $result.Provider | Should -Be 'vllm'
        $result.Response | Should -Be 'vllm response'
    }
}

AfterAll {
    Remove-Module PC-AI.LLM -Force -ErrorAction SilentlyContinue
}
