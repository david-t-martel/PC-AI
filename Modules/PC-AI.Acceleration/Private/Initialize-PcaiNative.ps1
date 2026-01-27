#Requires -Version 7.0
<#
.SYNOPSIS
    Initializes PCAI Native DLLs for high-performance operations

.DESCRIPTION
    Loads the native Rust DLLs and C# P/Invoke wrapper for:
    - pcai_core_lib.dll - Unified Core engine (Search, Duplicates, System)
    - PcaiNative.dll    - Managed C# bridge

    These provide 5-15x speedup over PowerShell equivalents.

    IMPORTANT: Requires PowerShell 7+ (.NET 8) for the C# wrapper to load.
#>

# Module-level state for native tools
$script:PcaiNativeLoaded = $false
$script:PcaiNativeVersion = $null
$script:PcaiNativeDllPath = $null

function Initialize-PcaiNative {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:PcaiNativeLoaded -and -not $Force) {
        Write-Verbose 'PCAI Native already loaded, skipping initialization'
        return $true
    }

    # Verify PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "PCAI Native requires PowerShell 7+ (you have $($PSVersionTable.PSVersion))"
        $script:PcaiNativeLoaded = $false
        return $false
    }

    Write-Verbose 'Initializing PCAI Native tools...'

    # Find DLL locations
    $searchPaths = @(
        (Join-Path $PSScriptRoot '..\..\..\bin')                    # PC_AI\bin
        (Join-Path $PSScriptRoot '..\..\..\..\Native\bin')          # Native\bin relative
        (Join-Path $env:USERPROFILE 'PC_AI\bin')                     # User bin
        "$env:USERPROFILE\bin"                                       # General user bin
    )

    $dllPath = $null
    foreach ($searchPath in $searchPaths) {
        $resolved = Resolve-Path -Path $searchPath -ErrorAction SilentlyContinue
        if ($resolved) {
            $coreDll = Join-Path $resolved.Path 'pcai_core_lib.dll'
            $wrapperDll = Join-Path $resolved.Path 'PcaiNative.dll'

            # Specialized DLLs
            $fsDll = Join-Path $resolved.Path 'pcai_fs.dll'
            $perfDll = Join-Path $resolved.Path 'pcai_performance.dll'
            $sysDll = Join-Path $resolved.Path 'pcai_system.dll'

            if ((Test-Path $coreDll) -and (Test-Path $wrapperDll)) {
                $dllPath = $resolved.Path
                break
            }
        }
    }

    if (-not $dllPath) {
        Write-Verbose 'PCAI Native DLLs (Core or Wrapper) not found in search paths'
        $script:PcaiNativeLoaded = $false
        return $false
    }

    Write-Verbose "Found PCAI Native DLLs at: $dllPath"
    $script:PcaiNativeDllPath = $dllPath

    try {
        # CRITICAL: Add the DLL directory to the process PATH so native DLLs can be found
        # This allows the C# wrapper to locate specialized Rust DLLs
        $currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'Process')
        if ($currentPath -notlike "*$dllPath*") {
            [System.Environment]::SetEnvironmentVariable('PATH', "$dllPath;$currentPath", 'Process')
            Write-Verbose "Added $dllPath to process PATH"
        }

        # Load the C# wrapper assembly
        $wrapperPath = Join-Path $dllPath 'PcaiNative.dll'

        # Check if already loaded
        $loadedAssembly = [System.AppDomain]::CurrentDomain.GetAssemblies() |
            Where-Object { $_.GetName().Name -eq 'PcaiNative' }

        if (-not $loadedAssembly) {
            Add-Type -Path $wrapperPath -ErrorAction Stop
            Write-Verbose 'Loaded PcaiNative.dll assembly'
        } else {
            Write-Verbose 'PcaiNative assembly already loaded'
        }

        # Test core availability
        if ([PcaiNative.PcaiCore]::IsAvailable) {
            $script:PcaiNativeVersion = [PcaiNative.PcaiCore]::Version
            Write-Verbose "PCAI System version: $($script:PcaiNativeVersion)"

            # Check specialized modules if available
            $fsAvailable = Test-Path (Join-Path $dllPath 'pcai_fs.dll')
            $perfAvailable = Test-Path (Join-Path $dllPath 'pcai_performance.dll')
            Write-Verbose "Specialized Modules: FS=$fsAvailable, Performance=$perfAvailable"

            $script:PcaiNativeLoaded = $true
            return $true
        } else {
            Write-Warning 'PCAI Core DLL loaded but not functional'
            $script:PcaiNativeLoaded = $false
            return $false
        }
    } catch {
        Write-Warning "Failed to load PCAI Native: $_"
        $script:PcaiNativeLoaded = $false
        return $false
    }
}

function Test-PcaiNativeAvailable {
    <#
    .SYNOPSIS
        Tests if PCAI Native tools are available and functional
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if (-not $script:PcaiNativeLoaded) {
        # Try to initialize
        $null = Initialize-PcaiNative
    }

    return $script:PcaiNativeLoaded
}

function Get-PcaiNativeStatus {
    <#
    .SYNOPSIS
        Gets detailed status of PCAI Native tools
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Ensure initialized
    $available = Test-PcaiNativeAvailable
    $dllPath = $script:PcaiNativeDllPath

    [PSCustomObject]@{
        Available       = $available
        Version         = $script:PcaiNativeVersion
        DllPath         = $dllPath
        CoreAvailable   = if ($available) { [PcaiNative.PcaiCore]::IsAvailable } else { $false }
        Modules         = if ($available) {
            [PSCustomObject]@{
                FS          = Test-Path (Join-Path $dllPath 'pcai_fs.dll')
                Performance = Test-Path (Join-Path $dllPath 'pcai_performance.dll')
                System      = Test-Path (Join-Path $dllPath 'pcai_system.dll')
            }
        } else { $null }
    }
}

function Invoke-PcaiNativeDuplicate {
    <#
    .SYNOPSIS
        Finds duplicate files using native parallel SHA-256 hashing
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateScript({ Test-Path $_ -PathType Container })]
        [string]$Path,

        [Parameter()]
        [int64]$MinimumSize = 0,

        [Parameter()]
        [string]$IncludePattern,

        [Parameter()]
        [string]$ExcludePattern,

        [Parameter()]
        [switch]$StatsOnly
    )

    if (-not (Test-PcaiNativeAvailable)) {
        throw 'PCAI Native tools not available.'
    }

    $resolvedPath = Resolve-Path $Path | Select-Object -ExpandProperty Path

    if ($StatsOnly) {
        throw "StatsOnly not supported in consolidated NativeDuplicate implementation"
    }

    $json = [PcaiNative.PcaiCore]::FindDuplicates($resolvedPath, [uint64]$MinimumSize)
    if ($json) {
        return ($json | ConvertFrom-Json)
    }
    return $null
}

function Invoke-PcaiNativeFileSearch {
    <#
    .SYNOPSIS
        Fast file search using native parallel directory walking
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [int64]$MaxResults = 0,

        [Parameter()]
        [switch]$StatsOnly
    )

    if (-not (Test-PcaiNativeAvailable)) {
        throw 'PCAI Native tools not available.'
    }

    $resolvedPath = if ($Path) {
        Resolve-Path $Path | Select-Object -ExpandProperty Path
    } else {
        $null
    }

    if ($StatsOnly) {
        throw "StatsOnly not supported in consolidated NativeFileSearch implementation"
    }

    $json = [PcaiNative.PcaiCore]::FindFiles($resolvedPath, $Pattern, [uint32]$MaxResults)
    if ($json) {
        return ($json | ConvertFrom-Json)
    }
    return $null
}

function Invoke-PcaiNativeContentSearch {
    <#
    .SYNOPSIS
        Fast content search using native parallel regex matching
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Pattern,

        [Parameter()]
        [string]$Path,

        [Parameter()]
        [string]$FilePattern,

        [Parameter()]
        [int64]$MaxResults = 0,

        [Parameter()]
        [int]$ContextLines = 0,

        [Parameter()]
        [switch]$StatsOnly
    )

    if (-not (Test-PcaiNativeAvailable)) {
        throw 'PCAI Native tools not available.'
    }

    $resolvedPath = if ($Path) {
        Resolve-Path $Path | Select-Object -ExpandProperty Path
    } else {
        $null
    }

    if ($StatsOnly) {
        throw "StatsOnly not supported in consolidated NativeContentSearch implementation"
    }

    $json = [PcaiNative.PcaiCore]::SearchContent($resolvedPath, $Pattern, $FilePattern, [uint32]$MaxResults, [uint32]$ContextLines)
    if ($json) {
        return ($json | ConvertFrom-Json)
    }
    return $null
}

function Invoke-PcaiNativeSystemInfo {
    <#
    .SYNOPSIS
        Native system interrogation for hardware and OS telemetry
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [switch]$MetricsOnly,

        [Parameter()]
        [switch]$HighFidelity
    )

    if (-not (Test-PcaiNativeAvailable)) { return $null }

    if ($HighFidelity) {
        $json = [PcaiNative.PcaiCore]::GetSystemTelemetryJson()
        if ($json) { return ($json | ConvertFrom-Json) }
        return $null
    }

    $json = if ($MetricsOnly) {
        [PcaiNative.PcaiCore]::QueryHardwareMetrics()
    } else {
        [PcaiNative.PcaiCore]::QuerySystemInfo()
    }

    if ($json) {
        return ($json | ConvertFrom-Json)
    }
    return $null
}

function Test-PcaiResourceSafety {
    <#
    .SYNOPSIS
        Checks if system resources are within safety limits (e.g. 80% load)
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [float]$GpuLimit = 0.8
    )

    if (-not (Test-PcaiNativeAvailable)) { return $true }
    return [PcaiNative.PcaiCore]::CheckResourceSafety($GpuLimit)
}

function Get-PcaiTokenEstimate {
    <#
    .SYNOPSIS
        Estimates the number of tokens in a string for Gemma-like models natively
    #>
    [CmdletBinding()]
    [OutputType([uint64])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [AllowEmptyString()]
        [string]$Text
    )

    if (-not (Test-PcaiNativeAvailable)) {
        # Fallback to simple words + 20% if native is unavailable
        return [uint64](($Text.Split(' ') | Where-Object { $_ }).Count * 1.2 + 1)
    }
    return [PcaiNative.PcaiCore]::EstimateTokens($Text)
}
