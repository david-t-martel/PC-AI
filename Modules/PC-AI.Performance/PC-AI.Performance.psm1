#Requires -Version 5.1

<#
.SYNOPSIS
    PC-AI Performance Module
    Bridges PowerShell to Rust/C# native modules for high-performance diagnostics.

.DESCRIPTION
    Provides cmdlets for:
    - Fast disk usage analysis
    - Low-overhead process monitoring
    - System memory statistics
#>


function Get-PcaiDiskUsage {
    <#
    .SYNOPSIS
        Gets disk usage statistics for a directory.
    .DESCRIPTION
        Uses native Rust traversal for high-performance analysis.
    .PARAMETER Path
        Directory to analyze. Defaults to current location.
    .PARAMETER Top
        Number of top subdirectories to return.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $PWD,
        [int]$Top = 10
    )

    Import-Module PC-AI.Common -ErrorAction SilentlyContinue
    if (-not (Initialize-PcaiNative)) { return }

    $Json = [PcaiNative.PerformanceModule]::GetDiskUsageJson($Path, $Top)
    if ($Json) {
        return $Json | ConvertFrom-Json
    }
}

function Get-PcaiTopProcess {
    <#
    .SYNOPSIS
        Gets top resource-consuming processes.
    .DESCRIPTION
        Returns a snapshot of processes sorted by CPU or Memory.
    #>
    [CmdletBinding()]
    param(
        [ValidateSet('memory', 'cpu')]
        [string]$SortBy = 'memory',
        [int]$Top = 20
    )

    Import-Module PC-AI.Common -ErrorAction SilentlyContinue
    if (-not (Initialize-PcaiNative)) { return }

    $Json = [PcaiNative.PerformanceModule]::GetTopProcessesJson($Top, $SortBy)
    if ($Json) {
        return $Json | ConvertFrom-Json
    }
}

function Get-PcaiMemoryStat {
    <#
    .SYNOPSIS
        Gets system memory statistics.
    #>
    [CmdletBinding()]
    param()

    Import-Module PC-AI.Common -ErrorAction SilentlyContinue
    if (-not (Initialize-PcaiNative)) { return }

    $Json = [PcaiNative.PerformanceModule]::GetMemoryStatsJson()
    if ($Json) {
        return $Json | ConvertFrom-Json
    }
}

function Test-PcaiNative {
    <#
    .SYNOPSIS
        Verifies native DLL is loaded and working.
    #>
    [CmdletBinding()]
    param()

    Import-Module PC-AI.Common -ErrorAction SilentlyContinue
    if (-not (Initialize-PcaiNative)) { return $false }

    return [PcaiNative.PerformanceModule]::Test()
}

Export-ModuleMember -Function Get-PcaiDiskUsage, Get-PcaiTopProcess, Get-PcaiMemoryStat, Test-PcaiNative
