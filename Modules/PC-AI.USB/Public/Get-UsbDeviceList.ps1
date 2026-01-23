#Requires -Version 5.1
<#
.SYNOPSIS
    Lists USB devices available for WSL attachment

.DESCRIPTION
    Gets list of USB devices using usbipd-win, with fallback to WMI.

.PARAMETER Filter
    Filter devices by name pattern

.EXAMPLE
    Get-UsbDeviceList
    Lists all USB devices

.EXAMPLE
    Get-UsbDeviceList -Filter "FTDI"
    Lists only FTDI devices

.OUTPUTS
    PSCustomObject[] with device information
#>
function Get-UsbDeviceList {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [string]$Filter
    )

    $results = @()

    # Try usbipd first
    if (Test-UsbIpdInstalled) {
        try {
            $output = & usbipd list 2>&1

            if ($LASTEXITCODE -eq 0 -and $output -notmatch 'Unhandled exception|ERROR_PATH_NOT_FOUND') {
                # Parse usbipd output
                $lines = $output -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^BUSID\s+VID:PID' }

                foreach ($line in $lines) {
                    if ($line -match '^(\d+-\d+)\s+([0-9a-fA-F]{4}:[0-9a-fA-F]{4})\s+(.+?)\s+(Not\s+shared|Shared|Attached)') {
                        $device = [PSCustomObject]@{
                            BusId       = $matches[1]
                            VID_PID     = $matches[2]
                            Description = $matches[3].Trim()
                            State       = $matches[4]
                            Source      = 'usbipd'
                        }

                        if (-not $Filter -or $device.Description -like "*$Filter*" -or $device.VID_PID -like "*$Filter*") {
                            $results += $device
                        }
                    }
                }

                if ($results.Count -gt 0) {
                    return $results
                }
            }
            else {
                Write-Warning "usbipd list failed. Using fallback enumeration."
            }
        }
        catch {
            Write-Warning "usbipd error: $_. Using fallback enumeration."
        }
    }
    else {
        Write-Warning "usbipd-win not installed. Using fallback enumeration."
    }

    # Fallback to WMI
    $wmiDevices = Get-UsbDevicesFallback

    if ($Filter) {
        $wmiDevices = $wmiDevices | Where-Object {
            $_.Description -like "*$Filter*" -or $_.VID_PID -like "*$Filter*"
        }
    }

    return $wmiDevices
}
