#Requires -Version 5.1
<#
.SYNOPSIS
    Gets devices with errors from Device Manager

.DESCRIPTION
    Queries Win32_PnPEntity for devices with ConfigManagerErrorCode != 0,
    indicating device or driver issues.

.PARAMETER IncludeOK
    Include devices with no errors (ConfigManagerErrorCode = 0)

.PARAMETER Class
    Filter by PNP device class (e.g., 'USB', 'Net', 'DiskDrive')

.EXAMPLE
    Get-DeviceErrors
    Returns all devices with errors

.EXAMPLE
    Get-DeviceErrors -Class 'USB'
    Returns only USB devices with errors

.OUTPUTS
    PSCustomObject[] with properties: Name, PNPClass, Manufacturer, ErrorCode, ErrorDescription, Severity, Status
#>
function Get-DeviceErrors {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$IncludeOK,

        [Parameter()]
        [string]$Class
    )

    try {
        $query = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop

        if (-not $IncludeOK) {
            $query = $query | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
        }

        if ($Class) {
            $query = $query | Where-Object { $_.PNPClass -eq $Class -or $_.Name -like "*$Class*" }
        }

        $results = $query | ForEach-Object {
            [PSCustomObject]@{
                Name             = $_.Name
                PNPClass         = $_.PNPClass
                Manufacturer     = $_.Manufacturer
                ErrorCode        = $_.ConfigManagerErrorCode
                ErrorDescription = Format-DeviceErrorCode -ErrorCode $_.ConfigManagerErrorCode
                Severity         = Get-SeverityFromErrorCode -ErrorCode $_.ConfigManagerErrorCode
                Status           = $_.Status
                DeviceID         = $_.DeviceID
            }
        }

        return $results | Sort-Object -Property @{Expression = 'Severity'; Descending = $true}, Name

    }
    catch {
        Write-Error "Failed to query PnP devices: $($_.Exception.Message)"
        return @()
    }
}
