<#
.SYNOPSIS
    Integration tests for tool schema coverage and routing quality.
#>

BeforeAll {
    $script:RepoRoot = Join-Path $PSScriptRoot '..\..'
    $script:ToolsPath = Join-Path $script:RepoRoot 'Config\pcai-tools.json'
    $script:ScenariosPath = Join-Path $script:RepoRoot 'Deploy\functiongemma-finetune\scenarios.json'

    $script:Tools = (Get-Content -Path $script:ToolsPath -Raw -Encoding UTF8 | ConvertFrom-Json).tools
    $script:ScenarioData = Get-Content -Path $script:ScenariosPath -Raw -Encoding UTF8 | ConvertFrom-Json
}

Describe "Router Tool Schema" -Tag 'Integration', 'Router', 'Quality' {
    It "Should include core agent tools" {
        $toolNames = $script:Tools | ForEach-Object { $_.function.name }
        $toolNames | Should -Contain 'SearchDocs'
        $toolNames | Should -Contain 'GetSystemInfo'
        $toolNames | Should -Contain 'SearchLogs'
    }

    It "Each tool should have at least one training scenario" {
        $toolNames = $script:Tools | ForEach-Object { $_.function.name }
        $scenarioTools = $script:ScenarioData.scenarios | Where-Object { $_.tool_name } | ForEach-Object { $_.tool_name }

        foreach ($tool in $toolNames) {
            $scenarioTools | Should -Contain $tool -Because "$tool should appear in scenarios.json"
        }
    }

    It "Should include both chat and diagnose scenarios" {
        $modes = $script:ScenarioData.scenarios | ForEach-Object { $_.mode }
        $modes | Should -Contain 'chat'
        $modes | Should -Contain 'diagnose'
    }
}
