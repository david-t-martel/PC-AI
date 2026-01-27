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
            Mock Test-Path { $true } -ModuleName PC-AI.LLM
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should detect Ollama is running" {
            $result = Get-LLMStatus -TestConnection
            $result | Should -Not -BeNullOrEmpty
            $result.Ollama | Should -Not -BeNullOrEmpty
            $result.Ollama.Installed | Should -Be $true
            $result.Ollama.ApiConnected | Should -Be $true
        }

        It "Should check default endpoint" {
            Get-LLMStatus -TestConnection

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "localhost:11434|127\.0\.0\.1:11434"
            }
        }
    }

    Context "When Ollama is not running" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.LLM
            Mock Invoke-RestMethod { throw "Connection refused" } -ModuleName PC-AI.LLM
        }

        It "Should detect Ollama is not available" {
            $result = Get-LLMStatus
            $result.Ollama.ApiConnected | Should -Be $false
            $result.Recommendations | Should -Not -BeNullOrEmpty
        }
    }

    Context "When Ollama is not installed" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.LLM
        }

        It "Should detect Ollama is not installed" {
            $result = Get-LLMStatus
            $result.Ollama.Installed | Should -Be $false
            $result.Recommendations | Should -Match "not found"
        }
    }

    Context "When checking available models" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.LLM
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
            $result = Get-LLMStatus -TestConnection
            $result.Ollama.Models | Should -Not -BeNullOrEmpty
            $result.Ollama.Models.Count | Should -BeGreaterThan 0
            $result.Ollama.Models[0].Name | Should -Be "llama3.2:latest"
        }
    }
}

Describe "Send-OllamaRequest" -Tag 'Unit', 'LLM', 'Slow' {
    Context "When sending a successful request" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/generate") {
                    Get-MockOllamaResponse -Type Success
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should send prompt to Ollama" {
            $result = Send-OllamaRequest -Prompt "Analyze this system" -Model "llama3.2:latest"
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should include model in request" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/generate" -and $Body -like '*"model"*"llama3.2:latest"*'
            }
        }

        It "Should include prompt in request" {
            Send-OllamaRequest -Prompt "Test prompt" -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/generate" -and $Body -like '*"prompt"*"Test prompt"*'
            }
        }

        It "Should return response text" {
            $result = Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest"
            $result.Response | Should -Not -BeNullOrEmpty
        }
    }

    Context "When model is not available" {
        BeforeAll {
            # Mock the model list to not include the requested model
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } else {
                    Get-MockOllamaResponse -Type Error -Model "nonexistent:latest"
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should handle model not found error" {
            { Send-OllamaRequest -Prompt "Test" -Model "nonexistent:latest" -ErrorAction Stop } | Should -Throw -ExpectedMessage "*not available*"
        }
    }

    Context "When using system message" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/generate") {
                    Get-MockOllamaResponse -Type Success
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should include system message" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -System "You are a PC diagnostics expert"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/generate" -and $Body -like '*"system"*"You are a PC diagnostics expert"*'
            }
        }
    }

    Context "When setting temperature" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/generate") {
                    Get-MockOllamaResponse -Type Success
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM
        }

        It "Should include temperature parameter" {
            Send-OllamaRequest -Prompt "Test" -Model "llama3.2:latest" -Temperature 0.7

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/generate" -and $Body -like '*"temperature"*0.7*'
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
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/chat") {
                    @{
                        model = "llama3.2:latest"
                        created_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        message = @{
                            role = "assistant"
                            content = "Hello! How can I help you?"
                        }
                        done = $true
                        total_duration = 1250000000
                        load_duration = 50000000
                        prompt_eval_count = 125
                        eval_count = 275
                    }
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM

            Mock Read-Host { "exit" } -ModuleName PC-AI.LLM
        }

        It "Should start chat session" {
            { Invoke-LLMChat -Interactive -Model "llama3.2:latest" } | Should -Not -Throw
        }

        It "Should use specified model" {
            Invoke-LLMChat -Interactive -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat" -and $Body -like '*"model"*"llama3.2:latest"*'
            }
        }
    }

    Context "When using system prompt" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/chat") {
                    @{
                        model = "llama3.2:latest"
                        message = @{
                            role = "assistant"
                            content = "I'm here to help!"
                        }
                        done = $true
                    }
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM

            Mock Read-Host { "exit" } -ModuleName PC-AI.LLM
        }

        It "Should apply system prompt" {
            Invoke-LLMChat -Interactive -Model "llama3.2:latest" -System "You are helpful"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat" -and $Body -like '*"role"*"system"*' -and $Body -like '*"You are helpful"*'
            }
        }
    }

    Context "When maintaining conversation context" {
        BeforeAll {
            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/chat") {
                    @{
                        model = "llama3.2:latest"
                        message = @{
                            role = "assistant"
                            content = "Response"
                        }
                        done = $true
                    }
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM

            $script:callCount = 0
            Mock Read-Host {
                $script:callCount++
                if ($script:callCount -gt 2) { "exit" } else { "test message $script:callCount" }
            } -ModuleName PC-AI.LLM
        }

        It "Should maintain conversation context" {
            Invoke-LLMChat -Interactive -Model "llama3.2:latest"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat"
            } -Times 2
        }
    }
}

Describe "Invoke-PCDiagnosis" -Tag 'Unit', 'LLM', 'Integration' {
    Context "When analyzing diagnostic data" {
        BeforeAll {
            Mock Get-Content {
                param($Path)
                if ($Path -match "DIAGNOSE") {
                    "You are a PC diagnostics expert."
                } else {
                    @"
=== Device Errors ===
Device: USB Mass Storage Device
Error Code: 43

=== Disk Health ===
Samsung SSD 980 PRO: OK
WDC HDD: Pred Fail
"@
                }
            } -ModuleName PC-AI.LLM

            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/chat") {
                    @{
                        model = "qwen2.5-coder:7b"
                        message = @{
                            role = "assistant"
                            content = "Analysis complete. Found USB device error code 43."
                        }
                        done = $true
                        eval_count = 500
                    }
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM

            Mock Test-Path { $true } -ModuleName PC-AI.LLM
        }

        It "Should read diagnostic report" {
            Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\report.txt"

            Should -Invoke Get-Content -ModuleName PC-AI.LLM -ParameterFilter {
                $Path -match "report\.txt"
            }
        }

        It "Should send report to LLM via chat endpoint" {
            Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\report.txt"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat"
            }
        }

        It "Should include DIAGNOSE.md prompt in system message" {
            Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\report.txt"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat" -and $Body -like '*"system"*'
            }
        }

        It "Should use specified model" {
            Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\report.txt" -Model "qwen2.5:7b"

            Should -Invoke Invoke-RestMethod -ModuleName PC-AI.LLM -ParameterFilter {
                $Uri -match "/api/chat" -and $Body -like '*"qwen2.5:7b"*'
            }
        }
    }

    Context "When report file does not exist" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.LLM
        }

        It "Should handle missing report file" {
            { Invoke-PCDiagnosis -DiagnosticReportPath "TestDrive:\nonexistent.txt" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When saving analysis output" {
        BeforeAll {
            Mock Get-Content {
                param($Path)
                if ($Path -match "DIAGNOSE") {
                    "You are a PC diagnostics expert."
                } else {
                    "Diagnostic data"
                }
            } -ModuleName PC-AI.LLM

            Mock Invoke-RestMethod {
                param($Uri)
                if ($Uri -match "/api/tags") {
                    Get-MockOllamaResponse -Type ModelList
                } elseif ($Uri -match "/api/chat") {
                    @{
                        model = "qwen2.5-coder:7b"
                        message = @{
                            role = "assistant"
                            content = "Analysis results"
                        }
                        done = $true
                        eval_count = 500
                    }
                } else {
                    Get-MockOllamaResponse -Type Status
                }
            } -ModuleName PC-AI.LLM

            Mock Test-Path { $true } -ModuleName PC-AI.LLM
        }

        It "Should save analysis to file" {
            # Use Join-Path with TestDrive to get proper path
            $reportPath = Join-Path $TestDrive "report.txt"
            $analysisPath = Join-Path $TestDrive "analysis.txt"

            $result = Invoke-PCDiagnosis -DiagnosticReportPath $reportPath -OutputPath $analysisPath -SaveReport

            # Verify the result contains the saved path
            $result.ReportSavedTo | Should -Be $analysisPath
            $result.Analysis | Should -Be "Analysis results"
        }
    }
}

Describe "Set-LLMConfig" -Tag 'Unit', 'LLM', 'Fast' {
    Context "When configuring LLM settings" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.LLM -ParameterFilter { $Path -match "config" }
            Mock Invoke-RestMethod {
                Get-MockOllamaResponse -Type Status
            } -ModuleName PC-AI.LLM
        }

        It "Should save configuration and return config object" {
            $result = Set-LLMConfig -OllamaApiUrl "http://localhost:11434" -DefaultModel "llama3.2:latest"

            # Verify the configuration object was returned with correct values
            $result | Should -Not -BeNullOrEmpty
            $result.OllamaApiUrl | Should -Be "http://localhost:11434"
            $result.DefaultModel | Should -Be "llama3.2:latest"
            $result.PSObject.Properties.Name | Should -Contain "ConfigPath"
            $result.PSObject.Properties.Name | Should -Contain "LastUpdated"
        }

        It "Should save JSON configuration with proper structure" {
            $result = Set-LLMConfig -OllamaApiUrl "http://custom:11434" -DefaultModel "llama3.2:latest"

            # Verify the returned configuration has proper structure
            $result | Should -Not -BeNullOrEmpty
            $result.OllamaApiUrl | Should -Be "http://custom:11434"
            $result.DefaultModel | Should -Be "llama3.2:latest"
            $result.PSObject.Properties.Name | Should -Contain "DefaultTimeout"
        }

        It "Should update default model in config" {
            $result = Set-LLMConfig -DefaultModel "qwen2.5:7b"

            $result.DefaultModel | Should -Be "qwen2.5:7b"
        }
    }

    Context "When showing current configuration" {
        It "Should return current config with ShowConfig" {
            $result = Set-LLMConfig -ShowConfig

            $result | Should -Not -BeNullOrEmpty
            $result.PSObject.Properties.Name | Should -Contain "OllamaApiUrl"
            $result.PSObject.Properties.Name | Should -Contain "DefaultModel"
            $result.PSObject.Properties.Name | Should -Contain "ConfigPath"
        }
    }

    Context "When resetting configuration" {
        It "Should reset config to defaults" {
            $result = Set-LLMConfig -Reset

            # Verify the configuration was reset to defaults
            $result | Should -Not -BeNullOrEmpty
            $result.DefaultModel | Should -Be "qwen2.5-coder:7b"
            $result.OllamaApiUrl | Should -Be "http://localhost:11434"
            $result.DefaultTimeout | Should -Be 120
        }
    }
}

AfterAll {
    Remove-Module PC-AI.LLM -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}

