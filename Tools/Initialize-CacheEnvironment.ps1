#Requires -Version 5.1
<#
.SYNOPSIS
    Configure build caches (sccache/ccache) for Rust and C/C++ builds.

.PARAMETER DisableCache
    Disable cache configuration for the current session.

.PARAMETER Quiet
    Suppress informational output (still returns a result object).
#>
[CmdletBinding()]
param(
    [switch]$DisableCache,
    [switch]$Quiet
)

function Initialize-CacheEnvironment {
    [CmdletBinding()]
    param(
        [switch]$DisableCache,
        [switch]$Quiet
    )

    $result = [PSCustomObject]@{
        SccacheEnabled = $false
        CcacheEnabled  = $false
        CmakeLauncher  = $null
        Notes          = @()
    }

    if ($DisableCache) {
        $env:RUSTC_WRAPPER = ''
        $env:CMAKE_C_COMPILER_LAUNCHER = ''
        $env:CMAKE_CXX_COMPILER_LAUNCHER = ''
        $env:CMAKE_CUDA_COMPILER_LAUNCHER = ''
        $result.Notes += 'Cache disabled via parameter.'
        return $result
    }

    $sccacheCmd = Get-Command sccache -ErrorAction SilentlyContinue
    $disableSccache = $env:SCCACHE_DISABLE -eq '1'
    if (-not $disableSccache -and $sccacheCmd) {
        if (-not $env:RUSTC_WRAPPER) { $env:RUSTC_WRAPPER = 'sccache' }
        if (-not $env:SCCACHE_SERVER_PORT) { $env:SCCACHE_SERVER_PORT = '4226' }
        if (-not $env:SCCACHE_CACHE_COMPRESSION) { $env:SCCACHE_CACHE_COMPRESSION = 'zstd' }
        if (-not $env:SCCACHE_DIRECT) { $env:SCCACHE_DIRECT = 'true' }
        $result.SccacheEnabled = $true
    } elseif ($disableSccache) {
        $result.Notes += 'sccache disabled via SCCACHE_DISABLE.'
    } else {
        $result.Notes += 'sccache not found in PATH.'
    }

    $ccacheCmd = Get-Command ccache -ErrorAction SilentlyContinue
    if ($ccacheCmd) {
        $result.CcacheEnabled = $true
        if (-not $env:CCACHE_DIR) {
            $baseDir = if ($env:LOCALAPPDATA) {
                Join-Path $env:LOCALAPPDATA 'pcai\ccache'
            } else {
                Join-Path $env:USERPROFILE '.cache\ccache'
            }
            $env:CCACHE_DIR = $baseDir
        }
        if (-not $env:CCACHE_BASEDIR) {
            $repoRoot = Split-Path -Parent $PSScriptRoot
            $env:CCACHE_BASEDIR = $repoRoot
        }
        if (-not $env:CCACHE_COMPILERCHECK) { $env:CCACHE_COMPILERCHECK = 'content' }
        if (-not $env:CCACHE_SLOPPINESS) { $env:CCACHE_SLOPPINESS = 'time_macros' }
    } else {
        $result.Notes += 'ccache not found in PATH.'
    }

    $disableCudaLauncher = $env:PCAI_DISABLE_CUDA_LAUNCHER -eq '1'
    if ($disableCudaLauncher) {
        $env:CMAKE_CUDA_COMPILER_LAUNCHER = ''
    }
    if (-not $env:CMAKE_C_COMPILER_LAUNCHER -or -not $env:CMAKE_CXX_COMPILER_LAUNCHER -or (-not $env:CMAKE_CUDA_COMPILER_LAUNCHER -and -not $disableCudaLauncher)) {
        $preferCcache = $env:PCAI_PREFER_CCACHE -eq '1'
        if ($preferCcache -and $result.CcacheEnabled) {
            $launcher = 'ccache'
        } elseif ($result.SccacheEnabled) {
            $launcher = 'sccache'
        } elseif ($result.CcacheEnabled) {
            $launcher = 'ccache'
        } else {
            $launcher = $null
        }

        if ($launcher) {
            if (-not $env:CMAKE_C_COMPILER_LAUNCHER) { $env:CMAKE_C_COMPILER_LAUNCHER = $launcher }
            if (-not $env:CMAKE_CXX_COMPILER_LAUNCHER) { $env:CMAKE_CXX_COMPILER_LAUNCHER = $launcher }
            if (-not $disableCudaLauncher -and -not $env:CMAKE_CUDA_COMPILER_LAUNCHER) { $env:CMAKE_CUDA_COMPILER_LAUNCHER = $launcher }
            $result.CmakeLauncher = $launcher
        }
    } else {
        $result.CmakeLauncher = $env:CMAKE_C_COMPILER_LAUNCHER
    }

    if (-not $Quiet) {
        if ($result.SccacheEnabled) {
            Write-Host 'Cache: sccache enabled' -ForegroundColor Green
        } else {
            Write-Host 'Cache: sccache not configured' -ForegroundColor DarkGray
        }
        if ($result.CcacheEnabled) {
            Write-Host 'Cache: ccache enabled' -ForegroundColor Green
        } else {
            Write-Host 'Cache: ccache not configured' -ForegroundColor DarkGray
        }
        if ($result.CmakeLauncher) {
            Write-Host "CMake compiler launcher: $($result.CmakeLauncher)" -ForegroundColor DarkGray
        }
    }

    return $result
}

if ($MyInvocation.InvocationName -ne '.') {
    Initialize-CacheEnvironment -DisableCache:$DisableCache -Quiet:$Quiet
}
