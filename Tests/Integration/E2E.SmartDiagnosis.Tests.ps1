#Requires -Version 5.1
#Requires -Modules Pester

Describe "PC-AI Smart Diagnosis E2E" {
    BeforeAll {
        $script:PcaiRoot = "C:\Users\david\PC_AI"

        # Load necessary modules
        Import-Module (Join-Path $script:PcaiRoot "Modules\PC-AI.Acceleration\PC-AI.Acceleration.psm1") -Force
        Import-Module (Join-Path $script:PcaiRoot "Modules\PC-AI.LLM\PC-AI.LLM.psd1") -Force
    }

    It "Should find the Invoke-SmartDiagnosis command" {
        Get-Command Invoke-SmartDiagnosis | Should -Not -BeNull
    }

    It "Should match the required DIAGNOSE_TEMPLATE.json structure" {
        $TemplatePath = Join-Path "C:\Users\david\PC_AI" "Config\DIAGNOSE_TEMPLATE.json"
        $template = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json

        # Verify template basics
        $template.diagnosis_version | Should -Match '^[0-9.]+'
        $template.psobject.Properties.Name | Should -Contain "findings"
    }

    It "Should verify DIAGNOSE_LOGIC.md exists at root" {
        $LogicPath = Join-Path "C:\Users\david\PC_AI" "DIAGNOSE_LOGIC.md"
        Test-Path $LogicPath | Should -Be $true
        $diagLogic = Get-Content -Raw $LogicPath
        $diagLogic | Should -Match "6.1 Parse the Report"
    }
}
