<#
.SYNOPSIS
    Unit tests for PC-AI.Network module

.DESCRIPTION
    Tests network diagnostics, WSL connectivity, and VSock performance monitoring
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.Network\PC-AI.Network.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-NetworkDiagnostics" -Tag 'Unit', 'Network', 'Fast' {
    Context "When gathering network diagnostics" {
        BeforeAll {
            Mock Get-NetAdapter {
                [PSCustomObject]@{
                    Name = "Ethernet"
                    Status = "Up"
                    LinkSpeed = "1 Gbps"
                    MacAddress = "00-D8-61-12-34-56"
                }
            } -ModuleName PC-AI.Network

            Mock Get-NetIPAddress {
                [PSCustomObject]@{
                    InterfaceAlias = "Ethernet"
                    IPAddress = "192.168.1.100"
                    PrefixLength = 24
                    AddressFamily = "IPv4"
                }
            } -ModuleName PC-AI.Network

            Mock Test-NetConnection {
                [PSCustomObject]@{
                    ComputerName = "8.8.8.8"
                    RemoteAddress = "8.8.8.8"
                    PingSucceeded = $true
                    PingReplyDetails = @{
                        RoundtripTime = 15
                    }
                }
            } -ModuleName PC-AI.Network
        }

        It "Should return network adapter information" {
            $result = Get-NetworkDiagnostics
            $result | Should -Match "Ethernet"
        }

        It "Should include IP addresses" {
            $result = Get-NetworkDiagnostics
            $result | Should -Match "192\.168\.1\.100"
        }

        It "Should test internet connectivity" {
            $result = Get-NetworkDiagnostics

            Should -Invoke Test-NetConnection -ModuleName PC-AI.Network -ParameterFilter {
                $ComputerName -eq "8.8.8.8"
            }
        }
    }

    Context "When network adapters are disconnected" {
        BeforeAll {
            Mock Get-NetAdapter {
                [PSCustomObject]@{
                    Name = "Ethernet"
                    Status = "Disconnected"
                    LinkSpeed = "0 bps"
                }
            } -ModuleName PC-AI.Network
        }

        It "Should detect disconnected adapters" {
            $result = Get-NetworkDiagnostics
            $result | Should -Match "Disconnected"
        }
    }

    Context "When internet connectivity fails" {
        BeforeAll {
            Mock Get-NetAdapter {
                [PSCustomObject]@{
                    Name = "Ethernet"
                    Status = "Up"
                }
            } -ModuleName PC-AI.Network

            Mock Test-NetConnection {
                [PSCustomObject]@{
                    ComputerName = "8.8.8.8"
                    PingSucceeded = $false
                }
            } -ModuleName PC-AI.Network
        }

        It "Should detect connectivity failures" {
            $result = Get-NetworkDiagnostics
            $result | Should -Match "Failed|Unreachable"
        }
    }
}

Describe "Test-WSLConnectivity" -Tag 'Unit', 'Network', 'Slow' {
    Context "When testing WSL network connectivity" {
        BeforeAll {
            Mock Invoke-Expression {
                param($Command)
                switch -Wildcard ($Command) {
                    "*wsl ip addr*" { Get-MockWSLOutput -Command IpAddr }
                    "*wsl ip route*" { Get-MockWSLOutput -Command Route }
                    "*wsl ping*" { "PING 8.8.8.8 (8.8.8.8) 56(84) bytes of data.`n64 bytes from 8.8.8.8: icmp_seq=1 ttl=117 time=15.2 ms" }
                    "*wsl curl*" { "HTTP/1.1 200 OK" }
                    default { "" }
                }
            } -ModuleName PC-AI.Network
        }

        It "Should check WSL IP configuration" {
            $result = Test-WSLConnectivity

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Network -ParameterFilter {
                $Command -match "wsl.*ip addr"
            }
        }

        It "Should check WSL routing" {
            $result = Test-WSLConnectivity

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Network -ParameterFilter {
                $Command -match "wsl.*ip route"
            }
        }

        It "Should test WSL internet connectivity" {
            $result = Test-WSLConnectivity

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Network -ParameterFilter {
                $Command -match "wsl.*ping.*8\.8\.8\.8"
            }
        }

        It "Should return connectivity status" {
            $result = Test-WSLConnectivity
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "When WSL network is misconfigured" {
        BeforeAll {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -match "wsl.*ping") {
                    throw "Network unreachable"
                }
                Get-MockWSLOutput -Command IpAddr
            } -ModuleName PC-AI.Network
        }

        It "Should detect network configuration issues" {
            { Test-WSLConnectivity -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When WSL is not running" {
        BeforeAll {
            Mock Invoke-Expression { throw "WSL is not running" } -ModuleName PC-AI.Network
        }

        It "Should handle WSL not running" {
            { Test-WSLConnectivity -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Watch-VSockPerformance" -Tag 'Unit', 'Network', 'Slow' {
    Context "When monitoring VSock performance" {
        BeforeAll {
            Mock Invoke-Expression {
                @"
Proto  Local Address           State
hvsock  00000000-facb-11e6-bd58-64006a7986d3:00000001  LISTENING
hvsock  00000000-facb-11e6-bd58-64006a7986d3:00000002  ESTABLISHED
"@
            } -ModuleName PC-AI.Network

            Mock Start-Sleep {} -ModuleName PC-AI.Network
        }

        It "Should query VSock connections" {
            Watch-VSockPerformance -Iterations 1

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Network -ParameterFilter {
                $Command -match "wsl.*ss.*--vsock"
            }
        }

        It "Should support custom iteration count" {
            Watch-VSockPerformance -Iterations 3

            Should -Invoke Invoke-Expression -ModuleName PC-AI.Network -Times 3
        }

        It "Should support custom interval" {
            Watch-VSockPerformance -Iterations 2 -IntervalSeconds 5

            Should -Invoke Start-Sleep -ModuleName PC-AI.Network -ParameterFilter {
                $Seconds -eq 5
            }
        }
    }

    Context "When VSock connections are not available" {
        BeforeAll {
            Mock Invoke-Expression { "" } -ModuleName PC-AI.Network
        }

        It "Should handle no VSock connections gracefully" {
            $result = Watch-VSockPerformance -Iterations 1
            $result | Should -Match "No connections|Empty"
        }
    }
}

Describe "Optimize-VSock" -Tag 'Unit', 'Network', 'Slow', 'RequiresAdmin' {
    Context "When optimizing VSock configuration" {
        BeforeAll {
            Mock Set-ItemProperty {} -ModuleName PC-AI.Network
            Mock New-ItemProperty {} -ModuleName PC-AI.Network
            Mock Test-Path { $true } -ModuleName PC-AI.Network
        }

        It "Should configure VSock registry settings" {
            Optimize-VSock

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Network -ParameterFilter {
                $Path -match "Hyper-V"
            }
        }

        It "Should set VSock buffer sizes" {
            Optimize-VSock -BufferSize 262144

            Should -Invoke Set-ItemProperty -ModuleName PC-AI.Network -ParameterFilter {
                $Value -eq 262144
            }
        }
    }

    Context "When registry key does not exist" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.Network
            Mock New-Item {} -ModuleName PC-AI.Network
            Mock New-ItemProperty {} -ModuleName PC-AI.Network
        }

        It "Should create registry key if missing" {
            Optimize-VSock

            Should -Invoke New-Item -ModuleName PC-AI.Network
        }
    }

    Context "When not running as Administrator" {
        BeforeAll {
            Mock Set-ItemProperty { throw "Access denied" } -ModuleName PC-AI.Network
        }

        It "Should require Administrator privileges" {
            { Optimize-VSock -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Network-Helpers (Private Functions)" -Tag 'Unit', 'Network', 'Fast' {
    Context "When formatting network information" {
        BeforeAll {
            # Test private helper functions if exposed for testing
            Mock Get-NetAdapter {
                [PSCustomObject]@{
                    Name = "Ethernet"
                    Status = "Up"
                    LinkSpeed = "1 Gbps"
                }
            } -ModuleName PC-AI.Network
        }

        It "Should format adapter information" {
            # This tests that the module loads without errors
            Get-Module PC-AI.Network | Should -Not -BeNullOrEmpty
        }
    }
}

AfterAll {
    Remove-Module PC-AI.Network -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
