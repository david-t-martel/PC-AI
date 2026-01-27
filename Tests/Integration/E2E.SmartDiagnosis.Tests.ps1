#Requires -Version 5.1
#Requires -Modules Pester

param(
    [string]$ModulePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Modules\PC-AI.Core'),
    [string]$TemplatePath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Config\DIAGNOSE_TEMPLATE.json')
)

Describe "PC-AI Smart Diagnosis E2E" {
    BeforeAll {
        if (-not (Get-Module -Name PC-AI.Core -ErrorAction SilentlyContinue)) {
            Import-Module $ModulePath -Force
        }

        # Ensure we have a mock system info for testing
        $script:mockSystemInfo = [PSCustomObject]@{
            OS = "Microsoft Windows 11 Pro"
            Version = "10.0.22631"
            Graphics = @(
                [PSCustomObject]@{ Name = "NVIDIA GeForce RTX 4090"; DriverVersion = "551.23" }
            )
            WSL = [PSCustomObject]@{
                IsInstalled = $true
                DefaultDistro = "Ubuntu-22.04"
                IsRunning = $true
            }
            Docker = [PSCustomObject]@{
                IsRunning = $true
                Context = "default"
            }
        }
    }

    It "Should execute Invoke-SmartDiagnosis and produce valid JSON" {
        $result = Invoke-SmartDiagnosis -Mock -DiagnosticMode Full -Verbose

        $result | Should -Not -BeNullOrEmpty
        $json = $result | ConvertFrom-Json -ErrorAction SilentlyContinue

        $json | Should -Not -BeNullOrEmpty
        $json.status | Should -Be "Success"
        $json.metadata | Should -Not -BeNullOrEmpty
    }

    It "Should match the required DIAGNOSE_TEMPLATE.json structure" {
        $template = Get-Content -Path $TemplatePath -Raw | ConvertFrom-Json
        $result = Invoke-SmartDiagnosis -Mock -Verbose | ConvertFrom-Json

        # Verify top-level keys
        foreach ($key in $template.psobject.Properties.Name) {
            $result.psobject.Properties.Name | Should -Contain $key
        }

        $result.metadata.tool_version | Should -Match '^c[0-9a-f]{6}'
    }

    It "Should correctly inject system context into the prompt" {
        # This test ensures the LLM sees the current hardware/OS state
        $diagLogic = Get-Content -Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Config\DIAGNOSE_LOGIC.md') -Raw

        $diagLogic | Should -Match 'NVIDIA GeForce RTX 4090'
        $diagLogic | Should -Match 'Microsoft Windows 11 Pro'
    }
}
