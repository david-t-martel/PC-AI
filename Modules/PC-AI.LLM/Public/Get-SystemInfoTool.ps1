#Requires -Version 5.1

function Get-SystemInfoTool {
    <#
    .SYNOPSIS
        Active system interrogation tool for the AI agent.

    .DESCRIPTION
        Allows the agent to query specific WMI/CIM properties for devices,
        storage, and networking to verify hypotheses.

    .PARAMETER Category
        The category of information: Storage, Network, USB, BIOS, OS

    .PARAMETER Detail
        Specific detail requested (e.g., "FullStatus", "DriverVersion", "Capabilities")

    .EXAMPLE
        Get-SystemInfoTool -Category Network -Detail DriverVersion
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateSet('Storage', 'Network', 'USB', 'BIOS', 'OS')]
        [string]$Category,

        [Parameter()]
        [string]$Detail = 'Summary'
    )

    Write-Verbose "Interrogating $Category for $Detail"

    # Use native acceleration if available for general OS/System summary
    if ($Category -eq 'OS' -and $Detail -eq 'Summary' -and (Get-Command Invoke-PcaiNativeSystemInfo -ErrorAction SilentlyContinue)) {
        try {
            $nativeInfo = Invoke-PcaiNativeSystemInfo
            if ($nativeInfo) {
                return $nativeInfo | ConvertTo-Json -Depth 5
            }
        } catch {
            Write-Verbose "Native system info failed, falling back to CIM: $_"
        }
    }
    try {
        $result = switch ($Category) {
            'Storage' {
                $disks = Get-CimInstance Win32_DiskDrive
                if ($Detail -eq 'DriverVersion') {
                    $disks | Select-Object Model, InterfaceType, PNPDeviceID | ForEach-Object {
                        $pnp = Get-CimInstance Win32_PnPEntity -Filter "DeviceID = '$($_.PNPDeviceID.Replace('\', '\\'))'"
                        @{ Model = $_.Model; Driver = $pnp.DriverVersion }
                    }
                } else {
                    $disks | Select-Object Model, Size, Status, Partitions
                }
            }
            'Network' {
                $adapters = Get-CimInstance Win32_NetworkAdapter -Filter 'PhysicalAdapter = True'
                if ($Detail -eq 'DriverVersion') {
                    $adapters | ForEach-Object {
                        $pnp = Get-CimInstance Win32_PnPEntity -Filter "DeviceID = '$($_.PNPDeviceID.Replace('\', '\\'))'"
                        @{ Name = $_.Name; Driver = $pnp.DriverVersion; Provider = $pnp.Manufacturer }
                    }
                } else {
                    $adapters | Select-Object Name, NetEnabled, Speed, Status
                }
            }
            'USB' {
                $hubs = Get-CimInstance Win32_USBHub
                $hubs | Select-Object Name, DeviceID, Status
            }
            'BIOS' {
                Get-CimInstance Win32_BIOS | Select-Object Manufacturer, Version, ReleaseDate
            }
            'OS' {
                Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber, OSArchitecture
            }
        }

        return $result | ConvertTo-Json -Depth 5
    } catch {
        return @{ Error = $_.Exception.Message; Category = $Category } | ConvertTo-Json
    }
}
