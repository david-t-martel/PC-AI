#Requires -Version 7.0
<#
.SYNOPSIS
    Initializes PCAI Native DLLs for high-performance operations

.DESCRIPTION
    Loads the native Rust DLLs and C# P/Invoke wrapper for:
    - pcai_core_lib.dll - Core FFI utilities and string management
    - pcai_search.dll - Duplicate detection, file search, content search
    - PcaiNative.dll - C# wrapper with type-safe interfaces

    These provide 5-15x speedup over PowerShell equivalents.

    IMPORTANT: Requires PowerShell 7+ (.NET 8) for the C# wrapper to load.
#>

# Module-level state for native tools
$script:PcaiNativeLoaded = $false
$script:PcaiNativeVersion = $null
$script:PcaiSearchVersion = $null
$script:PcaiNativeDllPath = $null

function Initialize-PcaiNative {
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter()]
        [switch]$Force
    )

    if ($script:PcaiNativeLoaded -and -not $Force) {
        Write-Verbose "PCAI Native already loaded, skipping initialization"
        return $true
    }

    # Verify PowerShell 7+
    if ($PSVersionTable.PSVersion.Major -lt 7) {
        Write-Warning "PCAI Native requires PowerShell 7+ (you have $($PSVersionTable.PSVersion))"
        $script:PcaiNativeLoaded = $false
        return $false
    }

    Write-Verbose "Initializing PCAI Native tools..."

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
            $searchDll = Join-Path $resolved.Path 'pcai_search.dll'
            $wrapperDll = Join-Path $resolved.Path 'PcaiNative.dll'

            if ((Test-Path $coreDll) -and (Test-Path $searchDll) -and (Test-Path $wrapperDll)) {
                $dllPath = $resolved.Path
                break
            }
        }
    }

    if (-not $dllPath) {
        Write-Verbose "PCAI Native DLLs not found in search paths"
        $script:PcaiNativeLoaded = $false
        return $false
    }

    Write-Verbose "Found PCAI Native DLLs at: $dllPath"
    $script:PcaiNativeDllPath = $dllPath

    try {
        # CRITICAL: Add the DLL directory to the process PATH so native DLLs can be found
        # This allows the C# wrapper to locate pcai_core_lib.dll and pcai_search.dll
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
            Write-Verbose "Loaded PcaiNative.dll assembly"
        }
        else {
            Write-Verbose "PcaiNative assembly already loaded"
        }

        # Test core availability
        if ([PcaiNative.PcaiCore]::IsAvailable) {
            $script:PcaiNativeVersion = [PcaiNative.PcaiCore]::Version
            Write-Verbose "PCAI Core version: $($script:PcaiNativeVersion)"
        }
        else {
            Write-Warning "PCAI Core DLL loaded but not functional"
            $script:PcaiNativeLoaded = $false
            return $false
        }

        # Test search availability
        if ([PcaiNative.PcaiSearch]::IsAvailable) {
            $script:PcaiSearchVersion = [PcaiNative.PcaiSearch]::Version
            Write-Verbose "PCAI Search version: $($script:PcaiSearchVersion)"
        }
        else {
            Write-Warning "PCAI Search DLL loaded but not functional"
            $script:PcaiNativeLoaded = $false
            return $false
        }

        $script:PcaiNativeLoaded = $true
        Write-Verbose "PCAI Native initialization complete"
        return $true
    }
    catch {
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

    .OUTPUTS
        PSCustomObject with native tool status and versions
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param()

    # Ensure initialized
    $available = Test-PcaiNativeAvailable

    [PSCustomObject]@{
        Available       = $available
        CoreVersion     = $script:PcaiNativeVersion
        SearchVersion   = $script:PcaiSearchVersion
        DllPath         = $script:PcaiNativeDllPath
        CoreAvailable   = if ($available) { [PcaiNative.PcaiCore]::IsAvailable } else { $false }
        SearchAvailable = if ($available) { [PcaiNative.PcaiSearch]::IsAvailable } else { $false }
    }
}

function Invoke-PcaiNativeDuplicates {
    <#
    .SYNOPSIS
        Finds duplicate files using native parallel SHA-256 hashing

    .DESCRIPTION
        Uses the high-performance Rust implementation for 5-10x faster
        duplicate detection compared to PowerShell.

    .PARAMETER Path
        Root directory to search

    .PARAMETER MinimumSize
        Minimum file size in bytes (default: 0)

    .PARAMETER IncludePattern
        Glob pattern for files to include (e.g., "*.txt")

    .PARAMETER ExcludePattern
        Glob pattern for files to exclude (e.g., "*.tmp")

    .PARAMETER StatsOnly
        Return only statistics without the full file list

    .EXAMPLE
        Invoke-PcaiNativeDuplicates -Path "D:\Downloads"

    .EXAMPLE
        Invoke-PcaiNativeDuplicates -Path "C:\Photos" -IncludePattern "*.jpg" -MinimumSize 1MB

    .OUTPUTS
        DuplicateResult object with groups of duplicate files
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
        throw "PCAI Native tools not available. Build with: Native\build.ps1"
    }

    $resolvedPath = Resolve-Path $Path | Select-Object -ExpandProperty Path

    if ($StatsOnly) {
        return [PcaiNative.PcaiSearch]::FindDuplicatesStats(
            $resolvedPath,
            [uint64]$MinimumSize,
            $IncludePattern,
            $ExcludePattern
        )
    }
    else {
        return [PcaiNative.PcaiSearch]::FindDuplicates(
            $resolvedPath,
            [uint64]$MinimumSize,
            $IncludePattern,
            $ExcludePattern
        )
    }
}

function Invoke-PcaiNativeFileSearch {
    <#
    .SYNOPSIS
        Fast file search using native parallel directory walking

    .PARAMETER Path
        Root directory to search

    .PARAMETER Pattern
        Glob pattern to match (e.g., "*.txt", "**/*.rs")

    .PARAMETER MaxResults
        Maximum number of results (0 = unlimited)

    .PARAMETER StatsOnly
        Return only statistics without the file list
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
        throw "PCAI Native tools not available. Build with: Native\build.ps1"
    }

    $resolvedPath = if ($Path) {
        Resolve-Path $Path | Select-Object -ExpandProperty Path
    } else {
        $null
    }

    if ($StatsOnly) {
        return [PcaiNative.PcaiSearch]::FindFilesStats(
            $Pattern,
            $resolvedPath,
            [uint64]$MaxResults
        )
    }
    else {
        return [PcaiNative.PcaiSearch]::FindFiles(
            $Pattern,
            $resolvedPath,
            [uint64]$MaxResults
        )
    }
}

function Invoke-PcaiNativeContentSearch {
    <#
    .SYNOPSIS
        Fast content search using native parallel regex matching

    .PARAMETER Pattern
        Regex pattern to search for

    .PARAMETER Path
        Root directory to search

    .PARAMETER FilePattern
        Glob pattern for files to search (e.g., "*.log")

    .PARAMETER MaxResults
        Maximum number of matches (0 = unlimited)

    .PARAMETER ContextLines
        Number of context lines around matches

    .PARAMETER StatsOnly
        Return only statistics without match details
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
        throw "PCAI Native tools not available. Build with: Native\build.ps1"
    }

    $resolvedPath = if ($Path) {
        Resolve-Path $Path | Select-Object -ExpandProperty Path
    } else {
        $null
    }

    if ($StatsOnly) {
        return [PcaiNative.PcaiSearch]::SearchContentStats(
            $Pattern,
            $resolvedPath,
            $FilePattern,
            [uint64]$MaxResults
        )
    }
    else {
        return [PcaiNative.PcaiSearch]::SearchContent(
            $Pattern,
            $resolvedPath,
            $FilePattern,
            [uint64]$MaxResults,
            [uint32]$ContextLines
        )
    }
}
