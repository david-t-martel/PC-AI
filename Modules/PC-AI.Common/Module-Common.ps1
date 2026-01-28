#Requires -Version 7.0
<#
.SYNOPSIS
    Common utilities and shared state for PCAI modules.
#>

# Singleton initialization state
$script:PcaiNativeInitialized = $false

function Initialize-PcaiNative {
    <#
    .SYNOPSIS
        Singleton initialization for PCAI native components.
    #>
    [CmdletBinding()]
    param(
        [switch]$Force
    )

    if ($script:PcaiNativeInitialized -and -not $Force) {
        return $true
    }

    # Import the Acceleration module which contains the actual initialization logic
    # This prevents circular dependencies and centralizes DLL loading.
    $accelModule = Get-Module PC-AI.Acceleration
    if (-not $accelModule) {
        $accelModule = Import-Module PC-AI.Acceleration -PassThru -ErrorAction SilentlyContinue
    }

    if ($accelModule) {
        $result = & $accelModule { Initialize-PcaiNative -Force:$Force }
        $script:PcaiNativeInitialized = $result
        return $result
    }

    Write-Error "PC-AI.Acceleration module not found. Native initialization failed."
    return $false
}

Export-ModuleMember -Function Initialize-PcaiNative
