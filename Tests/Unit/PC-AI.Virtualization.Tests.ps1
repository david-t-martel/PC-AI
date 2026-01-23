<#
.SYNOPSIS
    Unit tests for PC-AI.Virtualization module

.DESCRIPTION
    Tests WSL status, Hyper-V detection, Docker diagnostics, and virtualization optimization
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.Virtualization\PC-AI.Virtualization.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-WSLStatus" -Tag 'Unit', 'Virtualization', 'Fast' {
    Context "When WSL is installed and running" {
        BeforeAll {
            Mock Invoke-Expression {
                param($Command)
                switch -Wildcard ($Command) {
                    "*wsl --status*" { Get-MockWSLOutput -Command Status }
                    "*wsl -l -v*" { Get-MockWSLOutput -Command List }
                    "*wsl --version*" { Get-MockWSLOutput -Command Version }
                    default { "" }
                }
            } -ModuleName PC-AI.Virtualization
        }

        It "Should return WSL status information" {
            $result = Get-WSLStatus
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should detect WSL version" {
            $result = Get-WSLStatus
            $result -match "Version: 2" | Should -Be $true
        }

        It "Should list distributions" {
            $result = Get-WSLStatus
            $result | Should -Match "Ubuntu"
        }
    }

    Context "When WSL is not installed" {
        BeforeAll {
            Mock Invoke-Expression { throw "wsl.exe not found" } -ModuleName PC-AI.Virtualization
        }

        It "Should handle WSL not installed gracefully" {
            { Get-WSLStatus -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When WSL is installed but not running" {
        BeforeAll {
            Mock Invoke-Expression {
                Get-MockWSLOutput -Command List | ForEach-Object {
                    $_ -replace "Running", "Stopped"
                }
            } -ModuleName PC-AI.Virtualization
        }

        It "Should detect stopped distributions" {
            $result = Get-WSLStatus
            $result | Should -Match "Stopped"
        }
    }
}

Describe "Get-HyperVStatus" -Tag 'Unit', 'Virtualization', 'Fast' {
    Context "When Hyper-V is enabled" {
        BeforeAll {
            Mock Get-WindowsOptionalFeature {
                [PSCustomObject]@{
                    FeatureName = "Microsoft-Hyper-V-All"
                    State = "Enabled"
                }
            } -ModuleName PC-AI.Virtualization

            Mock Get-Service {
                [PSCustomObject]@{
                    Name = "vmcompute"
                    Status = "Running"
                    StartType = "Automatic"
                }
            } -ModuleName PC-AI.Virtualization
        }

        It "Should detect Hyper-V is enabled" {
            $result = Get-HyperVStatus
            $result | Should -Match "Enabled"
        }

        It "Should check vmcompute service" {
            $result = Get-HyperVStatus
            $result | Should -Match "vmcompute"
        }
    }

    Context "When Hyper-V is disabled" {
        BeforeAll {
            Mock Get-WindowsOptionalFeature {
                [PSCustomObject]@{
                    FeatureName = "Microsoft-Hyper-V-All"
                    State = "Disabled"
                }
            } -ModuleName PC-AI.Virtualization
        }

        It "Should detect Hyper-V is disabled" {
            $result = Get-HyperVStatus
            $result | Should -Match "Disabled"
        }
    }

    Context "When running on Windows Home (no Hyper-V)" {
        BeforeAll {
            Mock Get-WindowsOptionalFeature { throw "Feature not found" } -ModuleName PC-AI.Virtualization
        }

        It "Should handle missing Hyper-V feature" {
            { Get-HyperVStatus -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Get-DockerStatus" -Tag 'Unit', 'Virtualization', 'Fast' {
    Context "When Docker Desktop is running" {
        BeforeAll {
            Mock Get-Process {
                [PSCustomObject]@{
                    Name = "Docker Desktop"
                    Id = 1234
                    CPU = 2.5
                    WorkingSet = 500MB
                }
            } -ModuleName PC-AI.Virtualization

            Mock Invoke-Expression { "Docker version 24.0.6, build ed223bc" } -ModuleName PC-AI.Virtualization
        }

        It "Should detect Docker is running" {
            $result = Get-DockerStatus
            $result | Should -Match "Running|version"
        }

        It "Should return Docker version" {
            $result = Get-DockerStatus
            $result | Should -Match "24\.0\.6"
        }
    }

    Context "When Docker Desktop is not running" {
        BeforeAll {
            Mock Get-Process { throw "Process not found" } -ModuleName PC-AI.Virtualization
        }

        It "Should detect Docker is not running" {
            { Get-DockerStatus -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When docker CLI is not available" {
        BeforeAll {
            Mock Get-Process {
                [PSCustomObject]@{
                    Name = "Docker Desktop"
                    Id = 1234
                }
            } -ModuleName PC-AI.Virtualization

            Mock Invoke-Expression { throw "docker: command not found" } -ModuleName PC-AI.Virtualization
        }

        It "Should handle docker CLI not available" {
            { Get-DockerStatus -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Optimize-WSLConfig" -Tag 'Unit', 'Virtualization', 'Slow' {
    BeforeAll {
        # Mock file operations
        Mock Test-Path { $true } -ModuleName PC-AI.Virtualization
        Mock Get-Content { "" } -ModuleName PC-AI.Virtualization
        Mock Set-Content {} -ModuleName PC-AI.Virtualization
    }

    Context "When .wslconfig does not exist" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.Virtualization -ParameterFilter { $Path -match "\.wslconfig" }
        }

        It "Should create new .wslconfig" {
            Optimize-WSLConfig -Memory 8 -Processors 4

            Should -Invoke Set-Content -ModuleName PC-AI.Virtualization -Times 1
        }
    }

    Context "When .wslconfig exists" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.Virtualization
            Mock Get-Content {
                @"
[wsl2]
memory=4GB
processors=2
"@
            } -ModuleName PC-AI.Virtualization
        }

        It "Should update existing .wslconfig" {
            Optimize-WSLConfig -Memory 8 -Processors 4

            Should -Invoke Get-Content -ModuleName PC-AI.Virtualization -Times 1
            Should -Invoke Set-Content -ModuleName PC-AI.Virtualization -Times 1
        }
    }

    Context "When invalid parameters are provided" {
        It "Should validate memory parameter" {
            { Optimize-WSLConfig -Memory 0 -ErrorAction Stop } | Should -Throw
        }

        It "Should validate processor parameter" {
            { Optimize-WSLConfig -Processors 0 -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Set-WSLDefenderExclusions" -Tag 'Unit', 'Virtualization', 'Slow', 'RequiresAdmin' {
    BeforeAll {
        # Mock Defender cmdlets
        Mock Add-MpPreference {} -ModuleName PC-AI.Virtualization
        Mock Get-MpPreference {
            [PSCustomObject]@{
                ExclusionPath = @()
            }
        } -ModuleName PC-AI.Virtualization
    }

    Context "When adding WSL exclusions" {
        It "Should add WSL directory exclusions" {
            Set-WSLDefenderExclusions

            Should -Invoke Add-MpPreference -ModuleName PC-AI.Virtualization -Times 1 -ParameterFilter {
                $ExclusionPath -contains "%USERPROFILE%\AppData\Local\Packages\CanonicalGroupLimited*"
            }
        }

        It "Should add WSL process exclusions" {
            Set-WSLDefenderExclusions

            Should -Invoke Add-MpPreference -ModuleName PC-AI.Virtualization -Times 1 -ParameterFilter {
                $ExclusionProcess -contains "wsl.exe"
            }
        }
    }

    Context "When exclusions already exist" {
        BeforeAll {
            Mock Get-MpPreference {
                [PSCustomObject]@{
                    ExclusionPath = @("%USERPROFILE%\AppData\Local\Packages\CanonicalGroupLimited*")
                }
            } -ModuleName PC-AI.Virtualization
        }

        It "Should skip existing exclusions" {
            Set-WSLDefenderExclusions

            Should -Invoke Add-MpPreference -ModuleName PC-AI.Virtualization -Times 0
        }
    }

    Context "When not running as Administrator" {
        BeforeAll {
            Mock Add-MpPreference { throw "Access denied" } -ModuleName PC-AI.Virtualization
        }

        It "Should require Administrator privileges" {
            { Set-WSLDefenderExclusions -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Repair-WSLNetworking" -Tag 'Unit', 'Virtualization', 'Slow' {
    BeforeAll {
        Mock Invoke-Expression {} -ModuleName PC-AI.Virtualization
        Mock Start-Sleep {} -ModuleName PC-AI.Virtualization
    }

    Context "When repairing WSL networking" {
        It "Should shutdown WSL" {
            Repair-WSLNetworking

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Virtualization -ParameterFilter {
                $Command -match "wsl --shutdown"
            }
        }

        It "Should reset network stack" {
            Repair-WSLNetworking

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Virtualization -ParameterFilter {
                $Command -match "netsh (winsock|int ip) reset"
            }
        }

        It "Should flush DNS" {
            Repair-WSLNetworking

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Virtualization -ParameterFilter {
                $Command -match "ipconfig /flushdns"
            }
        }
    }
}

Describe "Backup-WSLConfig" -Tag 'Unit', 'Virtualization', 'Fast' {
    BeforeAll {
        Mock Test-Path { $true } -ModuleName PC-AI.Virtualization
        Mock Copy-Item {} -ModuleName PC-AI.Virtualization
        Mock Get-Date { [datetime]"2024-01-15 10:30:00" }
    }

    Context "When backing up .wslconfig" {
        It "Should create timestamped backup" {
            Backup-WSLConfig

            Should -Invoke Copy-Item -ModuleName PC-AI.Virtualization -ParameterFilter {
                $Destination -match "\.wslconfig\.backup\."
            }
        }
    }

    Context "When .wslconfig does not exist" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.Virtualization
        }

        It "Should skip backup if config not found" {
            Backup-WSLConfig

            Should -Invoke Copy-Item -ModuleName PC-AI.Virtualization -Times 0
        }
    }
}

AfterAll {
    Remove-Module PC-AI.Virtualization -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
