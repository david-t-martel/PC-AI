#Requires -Version 5.1
<#+
.SYNOPSIS
    Wrapper for the external WSL network toolkit script.

.PARAMETER ScriptPath
    Path to the WSL network recovery script (default: C:\Scripts\wsl-network-recovery.ps1)

.PARAMETER Distribution
    WSL distribution name (passed through)

.PARAMETER Check
    Run basic connectivity checks

.PARAMETER Diagnose
    Run detailed diagnostics

.PARAMETER Repair
    Run repair sequence

.PARAMETER Full
    Run full repair sequence (including HNS reset)
#>
function Invoke-WSLNetworkToolkit {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ScriptPath = 'C:\Scripts\wsl-network-recovery.ps1',

        [Parameter()]
        [string]$Distribution,

        [Parameter()]
        [switch]$Check,

        [Parameter()]
        [switch]$Diagnose,

        [Parameter()]
        [switch]$Repair,

        [Parameter()]
        [switch]$Full,

        [Parameter()]
        [switch]$Optimize,

        [Parameter()]
        [switch]$ApplyConfig,

        [Parameter()]
        [switch]$TestNetworkingMode,

        [Parameter()]
        [ValidateSet('nat','mirrored','virtioproxy')]
        [string]$NetworkingMode,

        [Parameter()]
        [switch]$FixDns,

        [Parameter()]
        [switch]$RestartWsl,

        [Parameter()]
        [switch]$ResetAdapters,

        [Parameter()]
        [switch]$ResetWinsock,

        [Parameter()]
        [switch]$RestartHns,

        [Parameter()]
        [switch]$RestartWslService,

        [Parameter()]
        [switch]$DisableVmqOnWsl,

        [Parameter()]
        [switch]$Force
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "WSL toolkit script not found: $ScriptPath"
    }

    $args = @()
    if ($Distribution) { $args += @('-Distro', $Distribution) }

    if ($Check -or $Diagnose -or $Repair -or $Full -or $Optimize -or $ApplyConfig -or $TestNetworkingMode) {
        if ($Check) { $args += '-Check' }
        if ($Diagnose) { $args += '-Diagnose' }
        if ($Repair) { $args += '-Repair' }
        if ($Full) { $args += '-Full' }
        if ($Optimize) { $args += '-Optimize' }
        if ($ApplyConfig) { $args += '-ApplyConfig' }
        if ($TestNetworkingMode) { $args += '-TestNetworkingMode' }
    }
    else {
        $args += '-Check'
    }

    if ($NetworkingMode) { $args += @('-NetworkingMode', $NetworkingMode) }
    if ($FixDns) { $args += '-FixDns' }
    if ($RestartWsl) { $args += '-RestartWsl' }
    if ($ResetAdapters) { $args += '-ResetAdapters' }
    if ($ResetWinsock) { $args += '-ResetWinsock' }
    if ($RestartHns) { $args += '-RestartHns' }
    if ($RestartWslService) { $args += '-RestartWslService' }
    if ($DisableVmqOnWsl) { $args += '-DisableVmqOnWsl' }
    if ($Force) { $args += '-Force' }

    $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @args 2>&1
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        ScriptPath = $ScriptPath
        Arguments  = $args
        ExitCode   = $exitCode
        Output     = ($output | Out-String).Trim()
        Success    = ($exitCode -eq 0)
    }
}
