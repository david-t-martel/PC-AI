#Requires -Version 5.1

BeforeAll {
    $PcaiRoot = Join-Path $PSScriptRoot '..\\..\\'

    # Ensure Acceleration module is imported to load native types
    $AccelPath = Join-Path $PcaiRoot 'Modules\\PC-AI.Acceleration\\PC-AI.Acceleration.psd1'
    if (Test-Path $AccelPath) {
        Import-Module $AccelPath -Force -ErrorAction Stop
        # Initialize native if available
        if (Get-Command Initialize-PcaiNative -ErrorAction SilentlyContinue) {
            Initialize-PcaiNative -Force | Out-Null
        }
    }

    $ModulePath = Join-Path $PcaiRoot 'Modules\\PC-AI.LLM\\PC-AI.LLM.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop
    $script:LlmModule = Get-Module PC-AI.LLM
}

Describe "PC-AI Prompt Enrichment" {
    It "Should load and enrich CHAT.md with telemetry" {
        $prompt = & $script:LlmModule { Get-EnrichedSystemPrompt -Mode 'chat' }
        $prompt | Should -Not -BeNullOrEmpty
        $prompt | Should -Contain '[SYSTEM_RESOURCE_STATUS]'
        $prompt | Should -Contain 'CPU Usage:'
    }

    It "Should load and enrich DIAGNOSE.md with logic and telemetry" {
        $prompt = & $script:LlmModule { Get-EnrichedSystemPrompt -Mode 'diagnose' }
        $prompt | Should -Not -BeNullOrEmpty
        $prompt | Should -Contain '[SYSTEM_RESOURCE_STATUS]'
        $prompt | Should -Contain '## REASONING FRAMEWORK'
        $prompt | Should -Contain 'TOOL INTERPRETATION HINTS'
    }

    It "Should correctly call a tool by name using the mapping" {
        $Tools = @(
            @{
                function = @{
                    name = "test_tool"
                    description = "A test tool"
                }
                pcai_mapping = @{
                    cmdlet = "Get-Date"
                    module = $null
                    params = @{
                        Format = "yyyy"
                    }
                }
            } | ConvertTo-Json | ConvertFrom-Json
        )

        $result = & $script:LlmModule { Invoke-ToolByName -Name "test_tool" -Args @{} -Tools $args[0] -ModuleRoot "C:\\Users\\david\\PC_AI" } $Tools

        # Invoke-ToolByName returns a string, but if it's not a PSCustomObject it might just return the string representation
        $expected = Get-Date -Format "yyyy"
        $result | Should -Be $expected
    }

    It "Should handle missing tools gracefully" {
        # Provide at least one tool to satisfy [array] mandatory constraint if needed,
        # or just test with empty array if the function handles it.
        $result = & $script:LlmModule { Invoke-ToolByName -Name "missing_tool" -Args @{} -Tools @() -ModuleRoot "C:\\Users\\david\\PC_AI" }
        $result | Should -Contain "Unhandled tool"
    }
}
