<#
.SYNOPSIS
    Unit tests for the TUI launcher wrapper.
#>

BeforeAll {
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM\PC-AI.LLM.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop
}

Describe "Invoke-LLMChatTui" -Tag 'Unit', 'LLM', 'TUI' {
    It "Should throw when the TUI executable is missing" {
        Mock Test-Path { $false } -ModuleName PC-AI.LLM
        { Invoke-LLMChatTui -ErrorAction Stop } | Should -Throw -ExpectedMessage '*PcaiChatTui.exe not found*'
    }
}

AfterAll {
    Remove-Module PC-AI.LLM -Force -ErrorAction SilentlyContinue
}
