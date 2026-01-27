#Requires -Version 5.1
<#+
.SYNOPSIS
    Runs the PC_AI service host CLI.
#>
function Invoke-PcaiServiceHost {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string[]]$Args,

        [Parameter()]
        [string]$HostPath = 'C:\Users\david\PC_AI\Native\PcaiServiceHost\bin\Release\net8.0\PcaiServiceHost.dll'
    )

    if (-not (Test-Path $HostPath)) {
        throw "PcaiServiceHost not found at $HostPath"
    }

    $dotnet = (Get-Command dotnet -ErrorAction SilentlyContinue)?.Source
    if (-not $dotnet) {
        throw 'dotnet not found in PATH.'
    }

    $output = & $dotnet $HostPath @Args 2>&1
    $exitCode = $LASTEXITCODE

    return [PSCustomObject]@{
        HostPath = $HostPath
        Args = $Args
        ExitCode = $exitCode
        Output = ($output | Out-String).Trim()
        Success = ($exitCode -eq 0)
    }
}
