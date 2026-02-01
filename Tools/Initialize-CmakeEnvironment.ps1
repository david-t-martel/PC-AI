#Requires -Version 5.1
<#
.SYNOPSIS
    Normalizes CMake environment variables for the current session.

.DESCRIPTION
    Ensures CMAKE_ROOT points to the installed CMake share directory that matches
    the active cmake.exe version. Also aligns CMAKE_PREFIX_PATH and CMAKE_PROGRAM
    when they are missing or stale. Intended for build/doc pipelines.

.PARAMETER Quiet
    Suppress informational output (still returns a result object).
#>
[CmdletBinding()]
param(
    [switch]$Quiet
)

function Resolve-CmakeRoot {
    param([string]$CmakeExe)
    if (-not $CmakeExe) { return $null }

    $versionLine = & $CmakeExe --version 2>$null | Select-Object -First 1
    if (-not $versionLine) { return $null }
    if ($versionLine -match 'cmake version\s+([0-9]+)\.([0-9]+)') {
        $major = $Matches[1]
        $minor = $Matches[2]
    } else {
        return $null
    }

    $binDir = Split-Path -Parent $CmakeExe
    $shareDir = Join-Path $binDir '..\share'
    $shareDir = (Resolve-Path $shareDir -ErrorAction SilentlyContinue).Path
    if (-not $shareDir) { return $null }

    $expectedPrefix = "cmake-$major.$minor"
    $match = Get-ChildItem -Path $shareDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "$expectedPrefix*" } |
        Select-Object -First 1

    if ($match) { return $match.FullName }

    $fallback = Get-ChildItem -Path $shareDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'cmake-*' } |
        Sort-Object Name -Descending |
        Select-Object -First 1

    if ($fallback) { return $fallback.FullName }
    return $null
}

function Convert-CmakePath {
    param([string]$Path)
    if (-not $Path) { return $null }
    return ($Path -replace '\\', '/')
}

function Resolve-LldLink {
    if ($env:CARGO_LLD_PATH -and (Test-Path $env:CARGO_LLD_PATH)) {
        return $env:CARGO_LLD_PATH
    }
    $default = 'C:\Program Files\LLVM\bin\lld-link.exe'
    if (Test-Path $default) { return $default }
    $fromPath = (Get-Command lld-link.exe -ErrorAction SilentlyContinue).Source
    if ($fromPath -and (Test-Path $fromPath)) { return $fromPath }
    return $null
}

function Initialize-CmakeEnvironment {
    [CmdletBinding()]
    param([switch]$Quiet)

    $notes = @()

    $cmakeCmds = Get-Command cmake -All -ErrorAction SilentlyContinue
    if (-not $cmakeCmds) {
        return [PSCustomObject]@{
            Found = $false
            CmakeExe = $null
            CmakeRoot = $null
            Updated = $false
            Notes = @('cmake.exe not found on PATH')
        }
    }

    $cmakeExe = $null
    $cmakeRoot = $null
    $candidates = $cmakeCmds | Select-Object -ExpandProperty Source -Unique
    foreach ($candidate in $candidates) {
        $root = Resolve-CmakeRoot -CmakeExe $candidate
        if ($root) {
            $cmakeExe = $candidate
            $cmakeRoot = $root
            break
        }
    }
    if (-not $cmakeExe) {
        $cmakeExe = $candidates | Select-Object -First 1
        $cmakeRoot = Resolve-CmakeRoot -CmakeExe $cmakeExe
    }
    $updated = $false

    if ($cmakeRoot) {
        $cmakeRoot = Convert-CmakePath -Path $cmakeRoot
        if ($env:CMAKE_ROOT -ne $cmakeRoot) {
            $env:CMAKE_ROOT = $cmakeRoot
            $env:CMAKE_ROOT_PowerToys_code = $cmakeRoot
            $updated = $true
        }
    }

    $cmakeBin = Split-Path -Parent $cmakeExe
    $cmakeBin = Convert-CmakePath -Path $cmakeBin
    if (-not $env:CMAKE_PREFIX_PATH -or ($env:CMAKE_PREFIX_PATH -notlike "*$cmakeBin*")) {
        $env:CMAKE_PREFIX_PATH = $cmakeBin
        $env:CMAKE_PREFIX_PATH_PowerToys_code = $cmakeBin
        $updated = $true
    }

    $cmakeExe = Convert-CmakePath -Path $cmakeExe
    if (-not $env:CMAKE_PROGRAM -or ($env:CMAKE_PROGRAM -ne $cmakeExe)) {
        $env:CMAKE_PROGRAM = $cmakeExe
        $env:CMAKE_PROGRAM_PowerToys_code = $cmakeExe
        $updated = $true
    }

    $useLld = ($env:PCAI_USE_LLD -eq '1') -or ($env:CARGO_USE_LLD -eq '1')
    if ($useLld) {
        $lldPath = Resolve-LldLink
        if ($lldPath) {
            $lldPath = Convert-CmakePath -Path $lldPath
            if ($env:CMAKE_LINKER -ne $lldPath) {
                $env:CMAKE_LINKER = $lldPath
                $env:CMAKE_LINKER_PowerToys_code = $lldPath
                $updated = $true
            }
        } else {
            $notes += 'lld-link not found for CMAKE_LINKER.'
        }
    }

    $result = [PSCustomObject]@{
        Found = $true
        CmakeExe = $cmakeExe
        CmakeRoot = $cmakeRoot
        Updated = $updated
        Notes = $notes
    }

    if (-not $Quiet) {
        Write-Host "CMake detected: $cmakeExe" -ForegroundColor Green
        if ($cmakeRoot) { Write-Host "  CMAKE_ROOT: $cmakeRoot" -ForegroundColor DarkGray }
    }

    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-CmakeEnvironment -Quiet:$Quiet
}
