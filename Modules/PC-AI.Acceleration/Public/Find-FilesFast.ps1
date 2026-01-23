#Requires -Version 5.1
<#
.SYNOPSIS
    Fast file finding using fd

.DESCRIPTION
    Finds files using fd (fast find alternative) when available,
    with fallback to Get-ChildItem. fd is typically 5-10x faster
    than PowerShell's Get-ChildItem for large directory trees.

.PARAMETER Path
    Root path to search from

.PARAMETER Pattern
    Filename pattern (supports regex)

.PARAMETER Extension
    File extension(s) to filter by

.PARAMETER Type
    Filter by type: file, directory, symlink

.PARAMETER MaxDepth
    Maximum directory depth to search

.PARAMETER Hidden
    Include hidden files

.PARAMETER Exclude
    Patterns to exclude

.EXAMPLE
    Find-FilesFast -Path "C:\Projects" -Extension "ps1"
    Finds all PowerShell files

.EXAMPLE
    Find-FilesFast -Path "D:\Data" -Pattern "backup" -Type file
    Finds files matching "backup" pattern

.OUTPUTS
    FileInfo[] or PSCustomObject[] with file information
#>
function Find-FilesFast {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo[]])]
    param(
        [Parameter(Position = 0)]
        [string]$Path = '.',

        [Parameter(Position = 1)]
        [string]$Pattern,

        [Parameter()]
        [string[]]$Extension,

        [Parameter()]
        [ValidateSet('file', 'directory', 'symlink', 'f', 'd', 'l')]
        [string]$Type,

        [Parameter()]
        [int]$MaxDepth = 0,

        [Parameter()]
        [switch]$Hidden,

        [Parameter()]
        [string[]]$Exclude,

        [Parameter()]
        [switch]$FullPath
    )

    $fdPath = Get-RustToolPath -ToolName 'fd'
    $useFd = $null -ne $fdPath -and (Test-Path $fdPath)

    if ($useFd) {
        return Find-WithFd @PSBoundParameters -FdPath $fdPath
    }
    else {
        Write-Verbose "fd not available, using Get-ChildItem fallback"
        return Find-WithGetChildItem @PSBoundParameters
    }
}

function Find-WithFd {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Pattern,
        [string[]]$Extension,
        [string]$Type,
        [int]$MaxDepth,
        [switch]$Hidden,
        [string[]]$Exclude,
        [switch]$FullPath,
        [string]$FdPath
    )

    $args = @()

    # Pattern (first positional argument) - use '.' for match-all if no pattern
    if ($Pattern) {
        # Convert glob patterns to regex if needed
        if ($Pattern -match '^\*\.(.+)$') {
            # *.ext pattern - use extension flag instead
            $args += '.'  # Match all
            $args += '-e'
            $args += $Matches[1]
        }
        else {
            $args += $Pattern
        }
    }
    else {
        $args += '.'  # Match all files
    }

    # Extensions (after pattern)
    foreach ($ext in $Extension) {
        $args += '-e'
        $args += $ext.TrimStart('*').TrimStart('.')
    }

    # Type
    if ($Type) {
        $args += '-t'
        switch ($Type) {
            'file'      { $args += 'f' }
            'directory' { $args += 'd' }
            'symlink'   { $args += 'l' }
            default     { $args += $Type }
        }
    }

    # Max depth
    if ($MaxDepth -gt 0) {
        $args += '-d'
        $args += $MaxDepth.ToString()
    }

    # Hidden files
    if ($Hidden) {
        $args += '-H'
    }

    # Exclusions
    foreach ($exc in $Exclude) {
        $args += '-E'
        $args += $exc
    }

    # Absolute paths (always use for reliable path resolution)
    $args += '-a'

    # Path (last positional argument)
    $args += $Path

    try {
        $output = & $FdPath @args 2>&1

        $results = @()
        foreach ($line in $output) {
            if ($line -and (Test-Path $line -ErrorAction SilentlyContinue)) {
                $results += Get-Item $line -ErrorAction SilentlyContinue
            }
        }
        return $results
    }
    catch {
        Write-Warning "fd search failed: $_"
        return @()
    }
}

function Find-WithGetChildItem {
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Pattern,
        [string[]]$Extension,
        [string]$Type,
        [int]$MaxDepth,
        [switch]$Hidden,
        [string[]]$Exclude,
        [switch]$FullPath
    )

    $params = @{
        Path    = $Path
        Recurse = $true
        ErrorAction = 'SilentlyContinue'
    }

    if ($MaxDepth -gt 0) {
        $params.Depth = $MaxDepth
    }

    if ($Hidden) {
        $params.Force = $true
    }

    # Get all items
    $items = Get-ChildItem @params

    # Filter by type
    if ($Type) {
        $items = switch ($Type) {
            { $_ -in 'file', 'f' }      { $items | Where-Object { -not $_.PSIsContainer } }
            { $_ -in 'directory', 'd' } { $items | Where-Object { $_.PSIsContainer } }
            default { $items }
        }
    }

    # Filter by pattern
    if ($Pattern) {
        $items = $items | Where-Object { $_.Name -match $Pattern }
    }

    # Filter by extension
    if ($Extension) {
        $extPatterns = $Extension | ForEach-Object { ".$($_.TrimStart('.'))" }
        $items = $items | Where-Object { $_.Extension -in $extPatterns }
    }

    # Exclude patterns
    foreach ($exc in $Exclude) {
        $items = $items | Where-Object { $_.FullName -notmatch [regex]::Escape($exc) }
    }

    return $items
}
