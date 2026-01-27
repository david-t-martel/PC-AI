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

$script:DllPath = $null

function Initialize-PcaiNative {
    [CmdletBinding()]
    param()

    if ($script:DllPath -and (Test-Path $script:DllPath)) {
        return
    }

    # Search paths for the DLL:
    # 1. ../../../bin (Standard project layout: Modules/PC-AI.Performance -> Root -> bin)
    # 2. $PSScriptRoot/bin (Module-local bin)
    $PossiblePaths = @(
        (Join-Path $PSScriptRoot '..\..\bin\PcaiNative.dll'),
        (Join-Path $PSScriptRoot 'bin\PcaiNative.dll')
    )

    foreach ($path in $PossiblePaths) {
        $fullPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($path)
        if (Test-Path $fullPath) {
            try {
                Add-Type -Path $fullPath -ErrorAction Stop
                $script:DllPath = $fullPath
                Write-Verbose "Loaded PcaiNative.dll from $fullPath"
                return
            } catch {
                Write-Warning "Found DLL at $fullPath but failed to load: $_"
            }
        }
    }

    Write-Warning 'PcaiNative.dll not found. Ensure the project is built (Native/build.ps1).'
}

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

    Initialize-PcaiNative
    if (-not $script:DllPath) { return }

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

    Initialize-PcaiNative
    if (-not $script:DllPath) { return }

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

    Initialize-PcaiNative
    if (-not $script:DllPath) { return }

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

    Initialize-PcaiNative
    if (-not $script:DllPath) { return $false }

    return [PcaiNative.PerformanceModule]::Test()
}

Export-ModuleMember -Function Get-PcaiDiskUsage, Get-PcaiTopProcess, Get-PcaiMemoryStat, Test-PcaiNative
