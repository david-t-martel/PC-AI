<#
.SYNOPSIS
    Unit tests for PC-AI.LLM module

.DESCRIPTION
    Tests Ollama connectivity, LLM chat functionality, and PC diagnosis using local LLMs
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.LLM\PC-AI.LLM.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-LLMStatus" -Tag 'Unit', 'LLM', 'Fast' {
    Context "When Ollama is running and accessible" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Status
            } -ModuleName PC-AI.LLM
        }

        It "Should detect Ollama is running" {
            $result = Get-LLMStatus
            $result | Should -Match "Running|OK|Available"
        }

        It "Should check default endpoint" {
            Get-LLMStatus

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "localhost:11434|127\.0\.0\.1:11434"
            }
        }
    }

    Context "When Ollama is not running" {
        BeforeAll {
            Mock Invoke-RestMethod { throw "Connection refused" } -ModuleName PC-AI.LLM
        }

        It "Should detect Ollama is not available" {
            { Get-LLMStatus -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When using custom endpoint" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Status
            } -ModuleName PC-AI.LLM
        }

        It "Should support custom endpoint" {
            Get-LLMStatus -Endpoint "http://custom:11434"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "custom:11434"
            }
        }
    }

    Context "When checking available models" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should list available models" {
            $result = Get-LLMStatus -ListModels
            $result | Should -Match "llama3\.2|qwen2\.5"
        }
    }
}

Describe "Send-OllamaRequest" -Tag 'Unit', 'LLM', 'Slow' {
    Context "When sending a successful request" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM
        }

        It "Should send prompt to Ollama" {
            $result = Send-OllamaRequest -Prompt "Analyze this system" -Model "llama3.2:latest"
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include model in request" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Body -match '"model"\s*:\s*"llama3\.2:latest"'
            }
        }

        It "Should include prompt in request" {
            Send-OllamaRequest -Prompt "Test prompt" -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Body -match '"prompt"\s*:\s*"Test prompt"'
            }
        }

        It "Should return response text" {
            $result = Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest"
            $result.response | Should -Not -BeNullOrEmpty
        }
    }

    Context "When model is not available" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Error -Model "nonexistent:latest"
            } -ModuleName PC-AI.LLM
        }

        It "Should handle model not found error" {
            $result = Send-OllamaRequest -Prompt "Test" -Model "nonexistent:latest" -ErrorAction SilentlyContinue
            $result.error | Should -Match "not found"
        }
    }

    Context "When using system message" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM
        }

        It "Should include system message" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -SystemMessage "You are a PC diagnostics expert"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Body -match '"system"\s*:\s*"You are a PC diagnostics expert"'
            }
        }
    }

    Context "When setting temperature" {
        BeforeAll {
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM
        }

        It "Should include temperature parameter" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -Temperature 0.7

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Body -match '"temperature"\s*:\s*0\.7'
            }
        }
    }

    Context "When Ollama is not responding" {
        BeforeAll {
            Mock Invoke-RestMethod { throw "Timeout" } -ModuleName PC-AI.LLM
        }

        It "Should handle timeout errors" {
            { Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Invoke-LLMChat" -Tag 'Unit', 'LLM', 'Slow' {
    Context "When starting an interactive chat" {
        BeforeAll {
            Mock Send-OllamaRequest {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM

            Mock Read-Host { "exit" } -ModuleName PC-AI.LLM
        }

        It "Should start chat session" {
            { Invoke-LLMChat -Model "llama3.2:latest" } | Should -Not -Throw
        }

        It "Should use specified model" {
            Invoke-LLMChat -Model "llama3.2:latest"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM -ParameterFilter {
                $Model -eq "llama3.2:latest"
            }
        }
    }

    Context "When using system prompt" {
        BeforeAll {
            Mock Send-OllamaRequest {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM

            Mock Read-Host { "exit" } -ModuleName PC-AI.LLM
        }

        It "Should apply system prompt" {
            Invoke-LLMChat -Model "llama3.2:latest" -SystemPrompt "You are helpful"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM -ParameterFilter {
                $SystemMessage -eq "You are helpful"
            }
        }
    }

    Context "When maintaining conversation context" {
        BeforeAll {
            Mock Send-OllamaRequest {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM

            $script:callCount = 0
            Mock Read-Host {
                $script:callCount++
                if ($script:callCount -gt 2) { "exit" } else { "test message $script:callCount" }
            } -ModuleName PC-AI.LLM
        }

        It "Should maintain conversation context" {
            Invoke-LLMChat -Model "llama3.2:latest"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM -Times 2
        }
    }
}

Describe "Invoke-PCDiagnosis" -Tag 'Unit', 'LLM', 'Integration' {
    Context "When analyzing diagnostic data" {
        BeforeAll {
            Mock Get-Content {
                @"
=== Device Errors ===
Device: USB Mass Storage Device
Error Code: 43

=== Disk Health ===
Samsung SSD 980 PRO: OK
WDC HDD: Pred Fail
"@
            } -ModuleName PC-AI.LLM

            Mock Send-OllamaRequest {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM
        }

        It "Should read diagnostic report" {
            Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt"

            Should -Invoke Get-Content -ModuleName PC-AI.LLM -ParameterFilter {
                $Path -match "report\.txt"
            }
        }

        It "Should send report to LLM" {
            Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM
        }

        It "Should include DIAGNOSE.md prompt" {
            Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM -ParameterFilter {
                $SystemMessage -match "PC diagnostic|hardware|diagnose"
            }
        }

        It "Should use specified model" {
            Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt" -Model "qwen2.5:7b"

            Should -Invoke Send-OllamaRequest -ModuleName PC-AI.LLM -ParameterFilter {
                $Model -eq "qwen2.5:7b"
            }
        }
    }

    Context "When report file does not exist" {
        BeforeAll {
            Mock Get-Content { throw "File not found" } -ModuleName PC-AI.LLM
        }

        It "Should handle missing report file" {
            { Invoke-PCDiagnosis -ReportPath "TestDrive:\nonexistent.txt" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When saving analysis output" {
        BeforeAll {
            Mock Get-Content {
                "Diagnostic data"
            } -ModuleName PC-AI.LLM

            Mock Send-OllamaRequest {
                Get-MockOllamaResponse -Type Success
            } -ModuleName PC-AI.LLM

            Mock Out-File {} -ModuleName PC-AI.LLM
        }

        It "Should save analysis to file" {
            Invoke-PCDiagnosis -ReportPath "TestDrive:\report.txt" -OutputPath "TestDrive:\analysis.txt"

            Should -Invoke Out-File -ModuleName PC-AI.LLM -ParameterFilter {
                $FilePath -match "analysis\.txt"
            }
        }
    }
}

Describe "Set-LLMConfig" -Tag 'Unit', 'LLM', 'Fast' {
    Context "When configuring LLM settings" {
        BeforeAll {
            Mock Set-Content {} -ModuleName PC-AI.LLM
            Mock Test-Path { $false } -ModuleName PC-AI.LLM -ParameterFilter { $Path -match "config" }
        }

        It "Should save configuration" {
            Set-LLMConfig -Endpoint "http://localhost:11434" -DefaultModel "llama3.2:latest"

            Should -Invoke Set-Content -ModuleName PC-AI.LLM
        }

        It "Should include endpoint in config" {
            Set-LLMConfig -Endpoint "http://custom:11434" -DefaultModel "llama3.2:latest"

            Should -Invoke Set-Content -ModuleName PC-AI.LLM -ParameterFilter {
                $Value -match '"endpoint"\s*:\s*"http://custom:11434"'
            }
        }

        It "Should include default model in config" {
            Set-LLMConfig -Endpoint "http://localhost:11434" -DefaultModel "qwen2.5:7b"

            Should -Invoke Set-Content -ModuleName PC-AI.LLM -ParameterFilter {
                $Value -match '"defaultModel"\s*:\s*"qwen2\.5:7b"'
            }
        }
    }

    Context "When loading existing configuration" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.LLM
            Mock Get-Content {
                '{"endpoint": "http://localhost:11434", "defaultModel": "llama3.2:latest"}'
            } -ModuleName PC-AI.LLM
        }

        It "Should load existing config" {
            $result = & (Get-Module PC-AI.LLM) { Get-LLMConfig }
            $result | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-Module PC-AI.LLM -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
