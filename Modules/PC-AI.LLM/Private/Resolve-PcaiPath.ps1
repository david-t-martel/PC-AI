#Requires -Version 5.1

<#
.SYNOPSIS
    Resolves PC_AI paths dynamically with environment variable support.

.PARAMETER PathType
    The type of path to resolve: Root, Config, HVSockConfig, Models, Logs

.OUTPUTS
    String path to the requested resource
#>
function Resolve-PcaiPath {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Root', 'Config', 'HVSockConfig', 'Models', 'Logs', 'Tools')]
        [string]$PathType
    )

    # Determine root path
    $root = $null

    # 1. Check environment variable
    if ($env:PCAI_ROOT) {
        $root = $env:PCAI_ROOT
    }
    # 2. Derive from module location
    elseif ($PSScriptRoot) {
        # Private -> PC-AI.LLM -> Modules -> PC_AI
        $root = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
    }
    # 3. Fallback to known location
    else {
        $root = 'C:\Users\david\PC_AI'
    }

    switch ($PathType) {
        'Root' { return $root }
        'Config' { return Join-Path $root 'Config' }
        'HVSockConfig' { return Join-Path $root 'Config\hvsock-proxy.conf' }
        'Models' { return Join-Path $root 'Models' }
        'Logs' { return Join-Path $root 'Reports\Logs' }
        'Tools' { return Join-Path $root 'Config\pcai-tools.json' }
        default { return $root }
    }
}
