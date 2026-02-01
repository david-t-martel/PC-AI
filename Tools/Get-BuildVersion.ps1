#Requires -Version 5.1
<#
.SYNOPSIS
    Generate build version information from git metadata.

.DESCRIPTION
    Extracts version information from git tags, commits, and timestamps
    for embedding into compiled binaries and build manifests.

    Version Format: {semver}-{commits}+{hash}.{timestamp}
    Example: 0.2.0-15+abc1234.20260201T143000Z

.PARAMETER Format
    Output format: Object (default), Json, Env, Cargo, CMake

.PARAMETER SetEnv
    Set environment variables for the current session.

.PARAMETER Quiet
    Suppress console output (still returns object).

.OUTPUTS
    PSCustomObject with version information:
    - Version: Full version string
    - SemVer: Semantic version (from tag or default)
    - Major, Minor, Patch: Version components
    - GitHash: Full commit hash
    - GitHashShort: 7-character short hash
    - GitBranch: Current branch name
    - GitTag: Most recent tag (if any)
    - CommitsSinceTag: Number of commits since tag
    - Timestamp: ISO 8601 UTC timestamp
    - TimestampUnix: Unix epoch timestamp
    - IsDirty: True if working tree has uncommitted changes
    - BuildType: 'release' if on tag, 'dev' otherwise

.EXAMPLE
    .\Get-BuildVersion.ps1
    Returns version object with all metadata.

.EXAMPLE
    .\Get-BuildVersion.ps1 -Format Env -SetEnv
    Sets PCAI_* environment variables for build scripts.

.EXAMPLE
    .\Get-BuildVersion.ps1 -Format Cargo
    Outputs Cargo-compatible environment variable exports.
#>

[CmdletBinding()]
param(
    [ValidateSet('Object', 'Json', 'Env', 'Cargo', 'CMake')]
    [string]$Format = 'Object',

    [switch]$SetEnv,
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

function Get-BuildVersion {
    [CmdletBinding()]
    param(
        [switch]$Quiet
    )

    $result = [ordered]@{
        Version         = ''
        SemVer          = '0.1.0'
        Major           = 0
        Minor           = 1
        Patch           = 0
        PreRelease      = ''
        GitHash         = ''
        GitHashShort    = ''
        GitBranch       = ''
        GitTag          = ''
        CommitsSinceTag = 0
        Timestamp       = ''
        TimestampUnix   = 0
        IsDirty         = $false
        BuildType       = 'dev'
        Features        = @()
    }

    # Get git information
    try {
        # Full commit hash
        $result.GitHash = (git rev-parse HEAD 2>$null) -replace '\s', ''
        if (-not $result.GitHash) { $result.GitHash = 'unknown' }

        # Short hash (7 chars)
        $result.GitHashShort = if ($result.GitHash -ne 'unknown') {
            $result.GitHash.Substring(0, 7)
        } else { 'unknown' }

        # Current branch
        $result.GitBranch = (git rev-parse --abbrev-ref HEAD 2>$null) -replace '\s', ''
        if (-not $result.GitBranch) { $result.GitBranch = 'unknown' }

        # Check for dirty working tree
        $status = git status --porcelain 2>$null
        $result.IsDirty = [bool]$status

        # Get most recent tag
        $tagInfo = git describe --tags --long --always 2>$null
        if ($tagInfo -match '^v?(\d+)\.(\d+)\.(\d+)(-([a-zA-Z0-9.-]+))?-(\d+)-g([a-f0-9]+)$') {
            $result.Major = [int]$Matches[1]
            $result.Minor = [int]$Matches[2]
            $result.Patch = [int]$Matches[3]
            $result.PreRelease = $Matches[5]
            $result.CommitsSinceTag = [int]$Matches[6]
            $result.GitTag = "v$($result.Major).$($result.Minor).$($result.Patch)"
            if ($result.PreRelease) {
                $result.GitTag += "-$($result.PreRelease)"
            }
        }
        elseif ($tagInfo -match '^v?(\d+)\.(\d+)\.(\d+)(-([a-zA-Z0-9.-]+))?$') {
            # Exact tag match (0 commits since tag)
            $result.Major = [int]$Matches[1]
            $result.Minor = [int]$Matches[2]
            $result.Patch = [int]$Matches[3]
            $result.PreRelease = $Matches[5]
            $result.CommitsSinceTag = 0
            $result.GitTag = "v$($result.Major).$($result.Minor).$($result.Patch)"
            if ($result.PreRelease) {
                $result.GitTag += "-$($result.PreRelease)"
            }
        }
        else {
            # No valid tag found, count all commits
            $commitCount = (git rev-list --count HEAD 2>$null) -replace '\s', ''
            if ($commitCount) {
                $result.CommitsSinceTag = [int]$commitCount
            }
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Warning "Git information unavailable: $($_.Exception.Message)"
        }
    }

    # Generate timestamp
    $now = [DateTime]::UtcNow
    $result.Timestamp = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $result.TimestampUnix = [int][double]::Parse((Get-Date $now -UFormat %s))

    # Build semantic version
    $result.SemVer = "$($result.Major).$($result.Minor).$($result.Patch)"
    if ($result.PreRelease) {
        $result.SemVer += "-$($result.PreRelease)"
    }

    # Determine build type
    if ($result.CommitsSinceTag -eq 0 -and $result.GitTag -and -not $result.IsDirty) {
        $result.BuildType = 'release'
    }
    elseif ($result.PreRelease) {
        $result.BuildType = 'prerelease'
    }
    else {
        $result.BuildType = 'dev'
    }

    # Generate full version string
    # Format: semver[-prerelease][.commits][+hash][.dirty]
    $version = $result.SemVer
    if ($result.CommitsSinceTag -gt 0) {
        $version += ".$($result.CommitsSinceTag)"
    }
    $version += "+$($result.GitHashShort)"
    if ($result.IsDirty) {
        $version += '.dirty'
    }
    $result.Version = $version

    return [PSCustomObject]$result
}

# Get version information
$versionInfo = Get-BuildVersion -Quiet:$Quiet

# Set environment variables if requested
if ($SetEnv) {
    $env:PCAI_VERSION = $versionInfo.Version
    $env:PCAI_SEMVER = $versionInfo.SemVer
    $env:PCAI_VERSION_MAJOR = $versionInfo.Major
    $env:PCAI_VERSION_MINOR = $versionInfo.Minor
    $env:PCAI_VERSION_PATCH = $versionInfo.Patch
    $env:PCAI_GIT_HASH = $versionInfo.GitHash
    $env:PCAI_GIT_HASH_SHORT = $versionInfo.GitHashShort
    $env:PCAI_GIT_BRANCH = $versionInfo.GitBranch
    $env:PCAI_GIT_TAG = $versionInfo.GitTag
    $env:PCAI_BUILD_TIMESTAMP = $versionInfo.Timestamp
    $env:PCAI_BUILD_TIMESTAMP_UNIX = $versionInfo.TimestampUnix
    $env:PCAI_BUILD_TYPE = $versionInfo.BuildType
    $env:PCAI_BUILD_DIRTY = if ($versionInfo.IsDirty) { '1' } else { '0' }

    # Also set for Cargo build.rs
    $env:PCAI_BUILD_VERSION = $versionInfo.Version

    if (-not $Quiet) {
        Write-Host "Set PCAI_* environment variables" -ForegroundColor Green
    }
}

# Output based on format
switch ($Format) {
    'Object' {
        return $versionInfo
    }
    'Json' {
        return $versionInfo | ConvertTo-Json -Depth 3
    }
    'Env' {
        $lines = @(
            "PCAI_VERSION=$($versionInfo.Version)"
            "PCAI_SEMVER=$($versionInfo.SemVer)"
            "PCAI_VERSION_MAJOR=$($versionInfo.Major)"
            "PCAI_VERSION_MINOR=$($versionInfo.Minor)"
            "PCAI_VERSION_PATCH=$($versionInfo.Patch)"
            "PCAI_GIT_HASH=$($versionInfo.GitHash)"
            "PCAI_GIT_HASH_SHORT=$($versionInfo.GitHashShort)"
            "PCAI_GIT_BRANCH=$($versionInfo.GitBranch)"
            "PCAI_GIT_TAG=$($versionInfo.GitTag)"
            "PCAI_BUILD_TIMESTAMP=$($versionInfo.Timestamp)"
            "PCAI_BUILD_TIMESTAMP_UNIX=$($versionInfo.TimestampUnix)"
            "PCAI_BUILD_TYPE=$($versionInfo.BuildType)"
            "PCAI_BUILD_DIRTY=$(if ($versionInfo.IsDirty) { '1' } else { '0' })"
        )
        return $lines -join "`n"
    }
    'Cargo' {
        # Output for Cargo build.rs consumption
        $lines = @(
            "cargo:rustc-env=PCAI_VERSION=$($versionInfo.Version)"
            "cargo:rustc-env=PCAI_SEMVER=$($versionInfo.SemVer)"
            "cargo:rustc-env=PCAI_GIT_HASH=$($versionInfo.GitHash)"
            "cargo:rustc-env=PCAI_GIT_HASH_SHORT=$($versionInfo.GitHashShort)"
            "cargo:rustc-env=PCAI_GIT_BRANCH=$($versionInfo.GitBranch)"
            "cargo:rustc-env=PCAI_BUILD_TIMESTAMP=$($versionInfo.Timestamp)"
            "cargo:rustc-env=PCAI_BUILD_TYPE=$($versionInfo.BuildType)"
        )
        return $lines -join "`n"
    }
    'CMake' {
        # Output for CMake consumption
        $lines = @(
            "set(PCAI_VERSION `"$($versionInfo.Version)`")"
            "set(PCAI_SEMVER `"$($versionInfo.SemVer)`")"
            "set(PCAI_VERSION_MAJOR $($versionInfo.Major))"
            "set(PCAI_VERSION_MINOR $($versionInfo.Minor))"
            "set(PCAI_VERSION_PATCH $($versionInfo.Patch))"
            "set(PCAI_GIT_HASH `"$($versionInfo.GitHash)`")"
            "set(PCAI_GIT_HASH_SHORT `"$($versionInfo.GitHashShort)`")"
            "set(PCAI_GIT_BRANCH `"$($versionInfo.GitBranch)`")"
            "set(PCAI_BUILD_TIMESTAMP `"$($versionInfo.Timestamp)`")"
            "set(PCAI_BUILD_TYPE `"$($versionInfo.BuildType)`")"
        )
        return $lines -join "`n"
    }
}
