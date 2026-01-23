<#
.SYNOPSIS
    Mock data factory functions for PC_AI testing

.DESCRIPTION
    Provides factory functions to generate realistic mock data for:
    - Device Manager entries (PnP entities)
    - SMART disk status
    - Windows Event Log entries
    - Network adapters
    - WSL command output
    - Ollama API responses
#>

# ConfigManagerErrorCode reference
$script:ConfigManagerErrorCodes = @{
    0 = "Device is working properly"
    1 = "Device is not configured correctly"
    10 = "Device cannot start"
    12 = "Cannot find enough free resources"
    22 = "Device is disabled"
    28 = "The drivers for this device are not installed"
    31 = "Device is not working properly"
    43 = "Windows has stopped this device because it has reported problems"
}

<#
.SYNOPSIS
    Creates a mock PnP device entity
#>
function New-MockPnPEntity {
    [CmdletBinding()]
    param(
        [string]$Name = "Generic USB Device",
        [string]$DeviceID = "USB\VID_1234&PID_5678\1234567890",
        [string]$Status = "OK",
        [int]$ConfigManagerErrorCode = 0,
        [string]$DriverVersion = "10.0.19041.1",
        [string]$Manufacturer = "Generic Manufacturer"
    )

    [PSCustomObject]@{
        Name = $Name
        DeviceID = $DeviceID
        Status = $Status
        ConfigManagerErrorCode = $ConfigManagerErrorCode
        ConfigManagerErrorDescription = $script:ConfigManagerErrorCodes[$ConfigManagerErrorCode]
        DriverVersion = $DriverVersion
        Manufacturer = $Manufacturer
        Present = $true
        PSComputerName = $env:COMPUTERNAME
    }
}

<#
.SYNOPSIS
    Returns pre-configured devices with various error states
#>
function Get-MockDevicesWithErrors {
    [CmdletBinding()]
    param()

    @(
        New-MockPnPEntity -Name "USB Mass Storage Device" -DeviceID "USB\VID_0781&PID_5567\123456" `
            -Status "Degraded" -ConfigManagerErrorCode 43 -Manufacturer "SanDisk"

        New-MockPnPEntity -Name "Intel(R) USB 3.0 eXtensible Host Controller" -DeviceID "PCI\VEN_8086&DEV_9CB1" `
            -Status "Error" -ConfigManagerErrorCode 10 -Manufacturer "Intel Corporation"

        New-MockPnPEntity -Name "Generic Bluetooth Radio" -DeviceID "USB\VID_8087&PID_0A2A\5&1234" `
            -Status "Unknown" -ConfigManagerErrorCode 28 -Manufacturer "Intel Corporation"

        New-MockPnPEntity -Name "Realtek PCIe GbE Family Controller" -DeviceID "PCI\VEN_10EC&DEV_8168" `
            -Status "OK" -ConfigManagerErrorCode 0 -Manufacturer "Realtek"
    )
}

<#
.SYNOPSIS
    Returns mock devices with no errors (healthy system)
#>
function Get-MockDevicesHealthy {
    [CmdletBinding()]
    param()

    @(
        New-MockPnPEntity -Name "Intel(R) Core(TM) i7-10700K CPU" -DeviceID "ACPI\GenuineIntel_-_Intel64_Family_6_Model_165" `
            -Status "OK" -ConfigManagerErrorCode 0 -Manufacturer "Intel"

        New-MockPnPEntity -Name "NVIDIA GeForce RTX 3080" -DeviceID "PCI\VEN_10DE&DEV_2206" `
            -Status "OK" -ConfigManagerErrorCode 0 -Manufacturer "NVIDIA"

        New-MockPnPEntity -Name "Samsung SSD 980 PRO 1TB" -DeviceID "SCSI\DISK&VEN_NVME&PROD_SAMSUNG_SSD_980_PRO_1TB" `
            -Status "OK" -ConfigManagerErrorCode 0 -Manufacturer "Samsung"
    )
}

<#
.SYNOPSIS
    Creates mock disk SMART output
#>
function Get-MockDiskSmartOutput {
    [CmdletBinding()]
    param(
        [ValidateSet('Healthy', 'Warning', 'Failed', 'Mixed')]
        [string]$Health = 'Healthy'
    )

    switch ($Health) {
        'Healthy' {
            @"
Model                          Status
Samsung SSD 980 PRO 1TB        OK
WDC WD40EZRZ-00GXCB0          OK
Seagate ST4000DM004-2CV104    OK
"@
        }
        'Warning' {
            @"
Model                          Status
Samsung SSD 980 PRO 1TB        OK
WDC WD40EZRZ-00GXCB0          Pred Fail
Seagate ST4000DM004-2CV104    OK
"@
        }
        'Failed' {
            @"
Model                          Status
Samsung SSD 980 PRO 1TB        OK
WDC WD40EZRZ-00GXCB0          Bad
Seagate ST4000DM004-2CV104    OK
"@
        }
        'Mixed' {
            @"
Model                          Status
Samsung SSD 980 PRO 1TB        OK
WDC WD40EZRZ-00GXCB0          Pred Fail
Seagate ST4000DM004-2CV104    Bad
"@
        }
    }
}

<#
.SYNOPSIS
    Creates a mock Windows Event Log entry
#>
function New-MockWinEvent {
    [CmdletBinding()]
    param(
        [int]$Id = 7,
        [string]$ProviderName = "disk",
        [ValidateSet('Error', 'Warning', 'Information')]
        [string]$Level = 'Error',
        [string]$Message = "The device, \Device\Harddisk1\DR1, has a bad block.",
        [datetime]$TimeCreated = (Get-Date).AddHours(-2)
    )

    $levelValue = switch ($Level) {
        'Error' { 2 }
        'Warning' { 3 }
        'Information' { 4 }
    }

    [PSCustomObject]@{
        Id = $Id
        ProviderName = $ProviderName
        Level = $levelValue
        LevelDisplayName = $Level
        Message = $Message
        TimeCreated = $TimeCreated
        LogName = 'System'
        MachineName = $env:COMPUTERNAME
    }
}

<#
.SYNOPSIS
    Returns pre-configured disk and USB error events
#>
function Get-MockDiskUsbEvents {
    [CmdletBinding()]
    param(
        [ValidateSet('None', 'DiskErrors', 'UsbErrors', 'Mixed')]
        [string]$ErrorType = 'Mixed'
    )

    $events = @()

    if ($ErrorType -in @('DiskErrors', 'Mixed')) {
        $events += New-MockWinEvent -Id 7 -ProviderName "disk" -Level Error `
            -Message "The device, \Device\Harddisk1\DR1, has a bad block." `
            -TimeCreated (Get-Date).AddHours(-3)

        $events += New-MockWinEvent -Id 153 -ProviderName "disk" -Level Warning `
            -Message "The IO operation at logical block address 0x1234567 for Disk 1 failed." `
            -TimeCreated (Get-Date).AddHours(-5)
    }

    if ($ErrorType -in @('UsbErrors', 'Mixed')) {
        $events += New-MockWinEvent -Id 411 -ProviderName "Microsoft-Windows-USB-USBHUB3" -Level Error `
            -Message "The device descriptor validation has failed." `
            -TimeCreated (Get-Date).AddHours(-1)

        $events += New-MockWinEvent -Id 413 -ProviderName "Microsoft-Windows-USB-USBHUB3" -Level Warning `
            -Message "The USB device has returned an invalid serial number string descriptor." `
            -TimeCreated (Get-Date).AddHours(-6)
    }

    if ($ErrorType -eq 'None') {
        # Return empty array
        return @()
    }

    return $events
}

<#
.SYNOPSIS
    Creates a mock network adapter entry
#>
function New-MockNetworkAdapter {
    [CmdletBinding()]
    param(
        [string]$Name = "Realtek PCIe GbE Family Controller",
        [string]$NetConnectionStatus = "Connected",
        [bool]$PhysicalAdapter = $true,
        [string]$MACAddress = "00:11:22:33:44:55",
        [long]$Speed = 1000000000  # 1 Gbps in bits per second
    )

    [PSCustomObject]@{
        Name = $Name
        NetConnectionStatus = $NetConnectionStatus
        PhysicalAdapter = $PhysicalAdapter
        MACAddress = $MACAddress
        Speed = $Speed
        NetEnabled = $true
        Status = "OK"
        AdapterType = if ($PhysicalAdapter) { "Ethernet 802.3" } else { "Virtual" }
        DeviceID = if ($PhysicalAdapter) { "1" } else { "100" }
    }
}

<#
.SYNOPSIS
    Returns mock network adapter collection
#>
function Get-MockNetworkAdapters {
    [CmdletBinding()]
    param(
        [switch]$IncludeVirtual
    )

    $adapters = @(
        New-MockNetworkAdapter -Name "Intel(R) Ethernet Connection I219-V" `
            -NetConnectionStatus "Connected" -PhysicalAdapter $true `
            -MACAddress "00:D8:61:12:34:56" -Speed 1000000000  # 1 Gbps
    )

    if ($IncludeVirtual) {
        $adapters += New-MockNetworkAdapter -Name "Hyper-V Virtual Ethernet Adapter" `
            -NetConnectionStatus "Connected" -PhysicalAdapter $false `
            -MACAddress "00:15:5D:AB:CD:EF" -Speed 10000000000  # 10 Gbps

        $adapters += New-MockNetworkAdapter -Name "WSL (vEthernet)" `
            -NetConnectionStatus "Connected" -PhysicalAdapter $false `
            -MACAddress "00:15:5D:12:34:56" -Speed 10000000000  # 10 Gbps
    }

    return $adapters
}

<#
.SYNOPSIS
    Returns mock WSL command output
#>
function Get-MockWSLOutput {
    [CmdletBinding()]
    param(
        [ValidateSet('Status', 'List', 'Version', 'IpAddr', 'Route')]
        [string]$Command = 'Status'
    )

    switch ($Command) {
        'Status' {
            @"
Default Distribution: Ubuntu
Default Version: 2
WSL2 Kernel Version: 5.15.90.1
"@
        }
        'List' {
            @"
  NAME            STATE           VERSION
* Ubuntu          Running         2
  Ubuntu-20.04    Stopped         2
  docker-desktop  Running         2
"@
        }
        'Version' {
            @"
WSL version: 2.0.9.0
Kernel version: 5.15.90.1
WSLg version: 1.0.59
MSRDC version: 1.2.4677
Direct3D version: 1.608.2-61064218
DXCore version: 10.0.25131.1002-220531-1700.rs-onecore-base2-hyp
Windows version: 10.0.19045.3693
"@
        }
        'IpAddr' {
            @"
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    inet 127.0.0.1/8 scope host lo
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP group default qlen 1000
    inet 172.28.16.5/20 brd 172.28.31.255 scope global eth0
"@
        }
        'Route' {
            @"
default via 172.28.16.1 dev eth0
172.28.16.0/20 dev eth0 proto kernel scope link src 172.28.16.5
"@
        }
    }
}

<#
.SYNOPSIS
    Returns mock Ollama API response
#>
function Get-MockOllamaResponse {
    [CmdletBinding()]
    param(
        [ValidateSet('Success', 'Error', 'ModelList', 'Status')]
        [string]$Type = 'Success',
        [string]$Model = 'llama3.2:latest'
    )

    switch ($Type) {
        'Success' {
            @{
                model = $Model
                created_at = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                response = "Based on the diagnostic data, I've identified the following issues: 1) USB device error code 43 indicating hardware failure..."
                done = $true
                context = @(1234, 5678, 9012)
                total_duration = 1250000000
                load_duration = 50000000
                prompt_eval_count = 125
                eval_count = 275
            }
        }
        'Error' {
            @{
                error = "model '$Model' not found, try pulling it first"
            }
        }
        'ModelList' {
            @{
                models = @(
                    @{
                        name = "llama3.2:latest"
                        modified_at = (Get-Date).AddDays(-5).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        size = 2640999999
                        digest = "sha256:abc123def456"
                    }
                    @{
                        name = "qwen2.5:7b"
                        modified_at = (Get-Date).AddDays(-10).ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
                        size = 4630000000
                        digest = "sha256:def789ghi012"
                    }
                )
            }
        }
        'Status' {
            @{
                status = "success"
            }
        }
    }
}

<#
.SYNOPSIS
    Returns mock usbipd list output
#>
function Get-MockUsbIpdOutput {
    [CmdletBinding()]
    param()

    @"
BUSID  VID:PID    DEVICE                                        STATE
2-1    0781:5567  USB Mass Storage Device                       Not shared
2-2    046d:c52b  Logitech Unifying Receiver                    Not shared
2-3    8087:0a2a  Intel(R) Wireless Bluetooth(R)                Not shared
2-4    0bda:5539  Integrated Webcam                             Not shared
"@
}

<#
.SYNOPSIS
    Returns mock disk space information
#>
function Get-MockDiskSpace {
    [CmdletBinding()]
    param(
        [ValidateSet('Healthy', 'LowSpace', 'Critical')]
        [string]$Status = 'Healthy'
    )

    switch ($Status) {
        'Healthy' {
            @(
                [PSCustomObject]@{
                    Drive = 'C:'
                    TotalSizeGB = 500
                    FreeSpaceGB = 350
                    PercentFree = 70
                }
                [PSCustomObject]@{
                    Drive = 'D:'
                    TotalSizeGB = 2000
                    FreeSpaceGB = 1500
                    PercentFree = 75
                }
            )
        }
        'LowSpace' {
            @(
                [PSCustomObject]@{
                    Drive = 'C:'
                    TotalSizeGB = 500
                    FreeSpaceGB = 40
                    PercentFree = 8
                }
            )
        }
        'Critical' {
            @(
                [PSCustomObject]@{
                    Drive = 'C:'
                    TotalSizeGB = 500
                    FreeSpaceGB = 15
                    PercentFree = 3
                }
            )
        }
    }
}

# Export all functions
Export-ModuleMember -Function @(
    'New-MockPnPEntity'
    'Get-MockDevicesWithErrors'
    'Get-MockDevicesHealthy'
    'Get-MockDiskSmartOutput'
    'New-MockWinEvent'
    'Get-MockDiskUsbEvents'
    'New-MockNetworkAdapter'
    'Get-MockNetworkAdapters'
    'Get-MockWSLOutput'
    'Get-MockOllamaResponse'
    'Get-MockUsbIpdOutput'
    'Get-MockDiskSpace'
)
