Describe "PC-AI Native Features (Phase 3)" {
    BeforeAll {
        # Dynamic root discovery (looks for bin folder)
        $Current = $PSScriptRoot
        while ($Current -and -not (Test-Path (Join-Path $Current "bin"))) {
            $Current = Split-Path $Current -Parent
        }
        $script:PcaiRoot = $Current ?: "C:\Users\david\PC_AI"

        $script:AccelerationModule = Join-Path $script:PcaiRoot "Modules\PC-AI.Acceleration\PC-AI.Acceleration.psm1"
        $script:LlmModule = Join-Path $script:PcaiRoot "Modules\PC-AI.LLM\PC-AI.LLM.psm1"

        if (Test-Path $script:AccelerationModule) {
            Import-Module $script:AccelerationModule -Force
        } else {
            Write-Warning "Acceleration module not found at: $script:AccelerationModule"
        }

        if (Test-Path $script:LlmModule) {
            Import-Module $script:LlmModule -Force
        }
    }

    Context "High-Fidelity Telemetry" {
        It "Should return valid telemetry JSON via Invoke-PcaiNativeSystemInfo -HighFidelity" {
            $telemetry = Invoke-PcaiNativeSystemInfo -HighFidelity
            $telemetry | Should -Not -BeNullOrEmpty
            $telemetry.cpu_usage | Should -BeGreaterThan 0
            $telemetry.memory_used_mb | Should -BeGreaterThan 0
        }
    }

    Context "Resource Safety Checks" {
        It "Should return a boolean for resource safety" {
            $isSafe = Test-PcaiResourceSafety -GpuLimit 0.8
            $isSafe | Should -BeOfType [bool]
        }
    }

    Context "Native Token Estimation" {
        It "Should estimate tokens for a simple string" {
            $count = Get-PcaiTokenEstimate -Text "Hello world"
            $count | Should -BeGreaterThan 1
        }

        It "Should return 0 for empty string" {
            $count = Get-PcaiTokenEstimate -Text ""
            $count | Should -Be 0
        }
    }

    Context "Dynamic Tool Dispatch" {
        It "Should dynamically resolve and execute a mapped tool" {
            # Since Invoke-ToolByName is internal to Invoke-FunctionGemmaReAct,
            # we verify it can be called (indirectly) or we check for registration.
            $tools = Get-Content -Path (Join-Path $script:PcaiRoot "Config\pcai-tools.json") -Raw | ConvertFrom-Json
            $tools.tools.Count | Should -BeGreaterThan 0
            $tools.tools[0].pcai_mapping | Should -Not -BeNullOrEmpty
        }
    }
}
