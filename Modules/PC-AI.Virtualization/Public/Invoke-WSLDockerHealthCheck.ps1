#Requires -Version 5.1
<#+
.SYNOPSIS
    Wrapper for the WSL/Docker health check script in C:\Scripts\Startup.
#>
function Invoke-WSLDockerHealthCheck {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter()]
        [string]$ScriptPath = 'C:\Scripts\Startup\wsl-docker-health-check.ps1',

        [Parameter()]
        [switch]$AutoRecover,

        [Parameter()]
        [switch]$Verbose,

        [Parameter()]
        [switch]$Quick
    )

    if (-not (Test-Path $ScriptPath)) {
        throw "WSL/Docker health check script not found: $ScriptPath"
    }

    $args = @()
    if ($AutoRecover) { $args += '-AutoRecover' }
    if ($Verbose) { $args += '-Verbose' }
    if ($Quick) { $args += '-Quick' }

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
