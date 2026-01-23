#Requires -Version 7.0
<#
.SYNOPSIS
    Internal helper functions for USB module
#>

function Test-UsbIpdInstalled {
    <#
    .SYNOPSIS
        Checks if usbipd-win is installed
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $usbipd = Get-Command usbipd.exe -ErrorAction SilentlyContinue
    return $null -ne $usbipd
}

function Test-IsAdministrator {
    <#
    .SYNOPSIS
        Checks if running as administrator
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-UsbDevicesFallback {
    <#
    .SYNOPSIS
        Gets USB devices via WMI when usbipd fails
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param()

    try {
        $devices = Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
            $_.Service -match 'usbser|ftdibus|usbccgp' -or
            $_.DeviceID -match '^USB\\VID_'
        } | ForEach-Object {
            $vidPid = $null
            if ($_.DeviceID -match 'VID_([0-9A-F]{4}).*PID_([0-9A-F]{4})') {
                $vidPid = "$($matches[1]):$($matches[2])"
            }

            [PSCustomObject]@{
                DeviceID    = $_.DeviceID
                Description = $_.Caption
                Status      = $_.Status
                VID_PID     = $vidPid
                Source      = 'WMI'
            }
        }

        return $devices
    }
    catch {
        Write-Error "Failed to enumerate USB devices via WMI: $_"
        return @()
    }
}
