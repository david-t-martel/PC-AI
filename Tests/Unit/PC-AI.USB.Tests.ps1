<#
.SYNOPSIS
    Unit tests for PC-AI.USB module

.DESCRIPTION
    Tests USB device listing with usbipd, WSL mounting/dismounting, and USB status monitoring
#>

BeforeAll {
    # Import module under test
    $ModulePath = Join-Path $PSScriptRoot '..\..\Modules\PC-AI.USB\PC-AI.USB.psd1'
    Import-Module $ModulePath -Force -ErrorAction Stop

    # Import mock data
    $MockDataPath = Join-Path $PSScriptRoot '..\Fixtures\MockData.psm1'
    Import-Module $MockDataPath -Force -ErrorAction Stop
}

Describe "Get-UsbDeviceList" -Tag 'Unit', 'USB', 'Fast' {
    Context "When usbipd is available" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.USB -ParameterFilter { $Path -match "usbipd" }
            Mock Invoke-Expression { Get-MockUsbIpdOutput } -ModuleName PC-AI.USB
        }

        It "Should return USB device list" {
            $result = Get-UsbDeviceList
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should parse BUSID" {
            $result = Get-UsbDeviceList
            $result | Should -Match '\d+-\d+'
        }

        It "Should parse VID:PID" {
            $result = Get-UsbDeviceList
            $result | Should -Match '[0-9a-fA-F]{4}:[0-9a-fA-F]{4}'
        }

        It "Should show device names" {
            $result = Get-UsbDeviceList
            $result | Should -Match 'USB Mass Storage Device'
        }

        It "Should show device state" {
            $result = Get-UsbDeviceList
            $result | Should -Match 'Not shared|Shared'
        }
    }

    Context "When usbipd is not installed" {
        BeforeAll {
            Mock Test-Path { $false } -ModuleName PC-AI.USB -ParameterFilter { $Path -match "usbipd" }
            Mock Get-CimInstance {
                @(
                    New-MockPnPEntity -Name "USB Mass Storage Device" -DeviceID "USB\VID_0781&PID_5567"
                )
            } -ModuleName PC-AI.USB
        }

        It "Should fall back to Get-CimInstance" {
            $result = Get-UsbDeviceList
            $result | Should -Not -BeNullOrEmpty
        }

        It "Should return USB devices from CIM" {
            $result = Get-UsbDeviceList
            $result | Should -Match 'USB'
        }
    }

    Context "When no USB devices are connected" {
        BeforeAll {
            Mock Test-Path { $true } -ModuleName PC-AI.USB
            Mock Invoke-Expression { "BUSID  VID:PID    DEVICE                                        STATE`n" } -ModuleName PC-AI.USB
        }

        It "Should handle no devices gracefully" {
            $result = Get-UsbDeviceList
            $result | Should -Match 'BUSID|No devices'
        }
    }
}

Describe "Mount-UsbToWSL" -Tag 'Unit', 'USB', 'Slow' {
    Context "When mounting USB device to WSL" {
        BeforeAll {
            Mock Invoke-Expression { "Device attached successfully" } -ModuleName PC-AI.USB
            Mock Start-Sleep {} -ModuleName PC-AI.USB
        }

        It "Should execute usbipd attach command" {
            Mount-UsbToWSL -BusId "2-1"

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "usbipd.*attach.*--busid.*2-1"
            }
        }

        It "Should support WSL distribution parameter" {
            Mount-UsbToWSL -BusId "2-1" -Distribution "Ubuntu"

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "--distribution.*Ubuntu"
            }
        }

        It "Should require valid BusId format" {
            { Mount-UsbToWSL -BusId "invalid" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When device is already attached" {
        BeforeAll {
            Mock Invoke-Expression { throw "Device is already attached" } -ModuleName PC-AI.USB
        }

        It "Should handle already attached error" {
            { Mount-UsbToWSL -BusId "2-1" -ErrorAction Stop } | Should -Throw -ExceptionType 'System.Management.Automation.RuntimeException'
        }
    }

    Context "When usbipd is not available" {
        BeforeAll {
            Mock Invoke-Expression { throw "usbipd: command not found" } -ModuleName PC-AI.USB
        }

        It "Should require usbipd to be installed" {
            { Mount-UsbToWSL -BusId "2-1" -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Dismount-UsbFromWSL" -Tag 'Unit', 'USB', 'Slow' {
    Context "When dismounting USB device from WSL" {
        BeforeAll {
            Mock Invoke-Expression { "Device detached successfully" } -ModuleName PC-AI.USB
        }

        It "Should execute usbipd detach command" {
            Dismount-UsbFromWSL -BusId "2-1"

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "usbipd.*detach.*--busid.*2-1"
            }
        }

        It "Should require valid BusId format" {
            { Dismount-UsbFromWSL -BusId "invalid" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When device is not attached" {
        BeforeAll {
            Mock Invoke-Expression { throw "Device is not attached" } -ModuleName PC-AI.USB
        }

        It "Should handle not attached error" {
            { Dismount-UsbFromWSL -BusId "2-1" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When AllDevices switch is used" {
        BeforeAll {
            Mock Invoke-Expression { "All devices detached" } -ModuleName PC-AI.USB
        }

        It "Should detach all devices" {
            Dismount-UsbFromWSL -AllDevices

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "usbipd.*detach.*--all"
            }
        }
    }
}

Describe "Get-UsbWSLStatus" -Tag 'Unit', 'USB', 'Fast' {
    Context "When checking USB devices attached to WSL" {
        BeforeAll {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -match "usbipd.*list") {
                    Get-MockUsbIpdOutput
                }
                elseif ($Command -match "wsl.*lsusb") {
                    @"
Bus 001 Device 002: ID 0781:5567 SanDisk Corp. USB Mass Storage Device
Bus 002 Device 001: ID 1d6b:0003 Linux Foundation 3.0 root hub
"@
                }
            } -ModuleName PC-AI.USB
        }

        It "Should check Windows USB status" {
            $result = Get-UsbWSLStatus

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "usbipd"
            }
        }

        It "Should check WSL USB status" {
            $result = Get-UsbWSLStatus

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "wsl.*lsusb"
            }
        }

        It "Should return status information" {
            $result = Get-UsbWSLStatus
            $result | Should -Not -BeNullOrEmpty
        }
    }

    Context "When WSL is not running" {
        BeforeAll {
            Mock Invoke-Expression {
                param($Command)
                if ($Command -match "wsl") {
                    throw "WSL is not running"
                }
                else {
                    Get-MockUsbIpdOutput
                }
            } -ModuleName PC-AI.USB
        }

        It "Should handle WSL not running" {
            { Get-UsbWSLStatus -ErrorAction Stop } | Should -Throw
        }
    }
}

Describe "Invoke-UsbBind" -Tag 'Unit', 'USB', 'Slow', 'RequiresAdmin' {
    Context "When binding USB device" {
        BeforeAll {
            Mock Invoke-Expression { "Device bound successfully" } -ModuleName PC-AI.USB
        }

        It "Should execute usbipd bind command" {
            Invoke-UsbBind -BusId "2-1"

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "usbipd.*bind.*--busid.*2-1"
            }
        }

        It "Should support Force parameter" {
            Invoke-UsbBind -BusId "2-1" -Force

            Should -Invoke Invoke-Expression -ModuleName PC-AI.USB -ParameterFilter {
                $Command -match "--force"
            }
        }

        It "Should require valid BusId format" {
            { Invoke-UsbBind -BusId "invalid" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When device is already bound" {
        BeforeAll {
            Mock Invoke-Expression { throw "Device is already bound" } -ModuleName PC-AI.USB
        }

        It "Should handle already bound error" {
            { Invoke-UsbBind -BusId "2-1" -ErrorAction Stop } | Should -Throw
        }
    }

    Context "When not running as Administrator" {
        BeforeAll {
            Mock Invoke-Expression { throw "Access denied. Administrator privileges required." } -ModuleName PC-AI.USB
        }

        It "Should require Administrator privileges" {
            { Invoke-UsbBind -BusId "2-1" -ErrorAction Stop } | Should -Throw -ExceptionType 'System.Management.Automation.RuntimeException'
        }
    }
}

Describe "Test-UsbIpd (Private Function)" -Tag 'Unit', 'USB', 'Fast' {
    Context "When checking usbipd availability" {
        BeforeAll {
            Mock Get-Command {
                [PSCustomObject]@{
                    Name = "usbipd"
                    CommandType = "Application"
                    Source = "C:\Program Files\usbipd-win\usbipd.exe"
                }
            } -ModuleName PC-AI.USB
        }

        It "Should return true when usbipd is available" {
            $result = & (Get-Module PC-AI.USB) { Test-UsbIpd }
            $result | Should -Be $true
        }
    }

    Context "When usbipd is not installed" {
        BeforeAll {
            Mock Get-Command { throw "Command not found" } -ModuleName PC-AI.USB
        }

        It "Should return false when usbipd is not available" {
            $result = & (Get-Module PC-AI.USB) { Test-UsbIpd }
            $result | Should -Be $false
        }
    }
}

AfterAll {
    Remove-Module PC-AI.USB -Force -ErrorAction SilentlyContinue
    Remove-Module MockData -Force -ErrorAction SilentlyContinue
}
