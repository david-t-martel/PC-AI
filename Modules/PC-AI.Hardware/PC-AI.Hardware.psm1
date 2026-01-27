#Requires -Version 5.1

<#
.SYNOPSIS
    PC-AI Hardware Diagnostics Module
    Provides granular cmdlets for querying system hardware health via CIM/WMI.
#>

function Get-PcDeviceError {
    <#
    .SYNOPSIS
        Gets devices reporting errors in Device Manager.
    #>
    [CmdletBinding()]
    param()

    try {
        $devices = Get-CimInstance Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.ConfigManagerErrorCode -ne 0 }

        if ($devices) {
            $devices | Select-Object Name, PNPClass, Manufacturer, ConfigManagerErrorCode, Status
        }
    } catch {
        Write-Error "Failed to query PnP devices: $_"
    }
}

function Get-PcDiskStatus {
    <#
    .SYNOPSIS
        Gets SMART status of physical disks.
    #>
    [CmdletBinding()]
    param()

    try {
        Get-CimInstance Win32_DiskDrive | Select-Object Model, Status, Size, MediaType
    } catch {
        Write-Error "Failed to query disk status: $_"
    }
}

function Get-PcUsbStatus {
    <#
    .SYNOPSIS
        Gets status of USB controllers and devices.
    #>
    [CmdletBinding()]
    param(
        [switch]$ErrorsOnly
    )

    try {
        $usb = Get-CimInstance Win32_PnPEntity |
            Where-Object { $_.PNPClass -eq 'USB' -or $_.Name -like '*USB*' }

        if ($ErrorsOnly) {
            $usb = $usb | Where-Object { $_.ConfigManagerErrorCode -ne 0 -or $_.Status -ne 'OK' }
        }

        $usb | Select-Object Name, PNPClass, Status, ConfigManagerErrorCode
    } catch {
        Write-Error "Failed to query USB devices: $_"
    }
}

function Get-PcNetworkStatus {
    <#
    .SYNOPSIS
        Gets status of physical network adapters.
    #>
    [CmdletBinding()]
    param()

    try {
        Get-CimInstance Win32_NetworkAdapter |
            Where-Object { $_.PhysicalAdapter -eq $true } |
            Select-Object Name, NetEnabled, Status, MACAddress, Speed
    } catch {
        Write-Error "Failed to query network adapters: $_"
    }
}

function Get-PcSystemEvent {
    <#
    .SYNOPSIS
        Gets recent critical system events related to hardware.
    .PARAMETER Days
        Number of past days to query. Default is 3.
    #>
    [CmdletBinding()]
    param(
        [int]$Days = 3
    )

    try {
        $startTime = (Get-Date).AddDays(-$Days)
        Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = 1, 2, 3
            StartTime = $startTime
        } -ErrorAction SilentlyContinue | Where-Object {
            $_.ProviderName -match 'disk|storahci|nvme|usbhub|USB|nvstor|iaStor|stornvme|partmgr'
        } | Select-Object -First 50 TimeCreated, ProviderName, Id, LevelDisplayName, Message
    } catch {
        Write-Warning "Failed to query System events (Admin rights required?): $_"
    }
}

Export-ModuleMember -Function Get-PcDeviceError, Get-PcDiskStatus, Get-PcUsbStatus, Get-PcNetworkStatus, Get-PcSystemEvents
