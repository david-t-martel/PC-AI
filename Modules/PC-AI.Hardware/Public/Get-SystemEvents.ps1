#Requires -Version 5.1
<#
.SYNOPSIS
    Gets system events related to disk and USB devices

.DESCRIPTION
    Queries Windows Event Log for disk, storage, and USB related errors
    and warnings from the last few days.

.PARAMETER Days
    Number of days to look back (default: 3)

.PARAMETER MaxEvents
    Maximum number of events to return (default: 50)

.PARAMETER IncludeInfo
    Include informational events (Level 4)

.EXAMPLE
    Get-SystemEvents
    Returns disk/USB errors from the last 3 days

.EXAMPLE
    Get-SystemEvents -Days 7 -MaxEvents 100
    Returns more events from a longer period

.OUTPUTS
    PSCustomObject[] with properties: TimeCreated, ProviderName, Id, Level, Message, Severity
#>
function Get-SystemEvents {
    [CmdletBinding()]
    [OutputType([PSCustomObject[]])]
    param(
        [Parameter()]
        [ValidateRange(1, 30)]
        [int]$Days = 3,

        [Parameter()]
        [ValidateRange(1, 500)]
        [int]$MaxEvents = 50,

        [Parameter()]
        [switch]$IncludeInfo
    )

    try {
        $startTime = (Get-Date).AddDays(-$Days)

        # Define event levels: 1=Critical, 2=Error, 3=Warning, 4=Information
        $levels = if ($IncludeInfo) { @(1, 2, 3, 4) } else { @(1, 2, 3) }

        $events = Get-WinEvent -FilterHashtable @{
            LogName   = 'System'
            Level     = $levels
            StartTime = $startTime
        } -ErrorAction SilentlyContinue | Where-Object {
            $_.ProviderName -match 'disk|storahci|nvme|usbhub|USB|nvstor|iaStor|stornvme|partmgr|ntfs|volmgr'
        } | Select-Object -First $MaxEvents

        if (-not $events -or $events.Count -eq 0) {
            Write-Verbose "No disk/USB-related events found in the last $Days days."
            return @()
        }

        $results = $events | ForEach-Object {
            # Determine severity from level
            $severity = switch ($_.Level) {
                1 { 'Critical' }
                2 { 'Error' }
                3 { 'Warning' }
                4 { 'Info' }
                default { 'Unknown' }
            }

            [PSCustomObject]@{
                TimeCreated  = $_.TimeCreated
                ProviderName = $_.ProviderName
                Id           = $_.Id
                Level        = $_.LevelDisplayName
                Severity     = $severity
                Message      = ($_.Message -split "`n")[0]  # First line only
                FullMessage  = $_.Message
            }
        }

        return $results | Sort-Object -Property TimeCreated -Descending

    }
    catch {
        Write-Error "Failed to query system events: $($_.Exception.Message)"
        return @()
    }
}
