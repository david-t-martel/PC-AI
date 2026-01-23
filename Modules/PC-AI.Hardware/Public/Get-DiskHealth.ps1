#Requires -Version 5.1
<#
.SYNOPSIS
    Gets disk health status including SMART information

.DESCRIPTION
    Queries disk drives for model, status, and health information.
    Uses both WMI/CIM and wmic for comprehensive status.

.PARAMETER IncludePartitions
    Include partition information for each disk

.EXAMPLE
    Get-DiskHealth
    Returns disk health status for all drives

.EXAMPLE
    Get-DiskHealth -IncludePartitions
    Returns disk health with partition details

.OUTPUTS
    PSCustomObject[] with properties: Model, Status, MediaType, Size, Partitions, Severity
#>
function Get-DiskHealth {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [switch]$IncludePartitions
    )

    try {
        # Get disk information via CIM
        $disks = Get-CimInstance -ClassName Win32_DiskDrive -ErrorAction Stop

        # Get SMART status via wmic (more reliable for SMART)
        $wmicOutput = $null
        try {
            $wmicOutput = wmic diskdrive get model, status 2>&1
        }
        catch {
            Write-Verbose "WMIC query failed: $_"
        }

        # Parse SMART status from wmic output
        $smartStatus = @{}
        if ($wmicOutput) {
            $lines = $wmicOutput -split "`n" | Where-Object { $_.Trim() -and $_ -notmatch '^Model\s+Status' }
            foreach ($line in $lines) {
                if ($line -match '(.+?)\s+(OK|Pred Fail|FAILING|Unknown|CAUTION)\s*$') {
                    $model = $matches[1].Trim()
                    $status = $matches[2].Trim()
                    $smartStatus[$model] = $status
                }
            }
        }

        $results = foreach ($disk in $disks) {
            # Determine SMART status
            $status = 'Unknown'
            if ($smartStatus.ContainsKey($disk.Model)) {
                $status = $smartStatus[$disk.Model]
            }
            elseif ($disk.Status) {
                $status = $disk.Status
            }

            # Calculate severity
            $severity = 'OK'
            if ($status -in @('Pred Fail', 'FAILING', 'PREDICTED FAIL')) {
                $severity = 'Critical'
            }
            elseif ($status -in @('CAUTION', 'Unknown')) {
                $severity = 'Warning'
            }

            # Get size in GB
            $sizeGB = if ($disk.Size) { [math]::Round($disk.Size / 1GB, 2) } else { 0 }

            $diskResult = [PSCustomObject]@{
                Model       = $disk.Model
                Status      = $status
                MediaType   = $disk.MediaType
                InterfaceType = $disk.InterfaceType
                SizeGB      = $sizeGB
                Partitions  = $disk.Partitions
                Severity    = $severity
                DeviceID    = $disk.DeviceID
                SerialNumber = $disk.SerialNumber
            }

            if ($IncludePartitions) {
                $partitions = Get-CimInstance -ClassName Win32_DiskPartition -Filter "DiskIndex=$($disk.Index)" -ErrorAction SilentlyContinue
                $diskResult | Add-Member -NotePropertyName 'PartitionDetails' -NotePropertyValue $partitions
            }

            $diskResult
        }

        return $results | Sort-Object -Property @{Expression = 'Severity'; Descending = $true}, Model

    }
    catch {
        Write-Error "Failed to query disk health: $($_.Exception.Message)"
        return @()
    }
}
