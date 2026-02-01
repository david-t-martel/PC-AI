#Requires -Version 5.1
<#
.SYNOPSIS
    Consolidated build script for pcai-inference with dual-backend support.

.DESCRIPTION
    Orchestrates building pcai-inference with llamacpp and/or mistralrs backends.
    Integrates sccache, ccache, MSVC, and CUDA environment initialization.

.PARAMETER Backend
    Which backend(s) to build: llamacpp, mistralrs, or all (default)

.PARAMETER Configuration
    Build configuration: Debug or Release (default)

.PARAMETER EnableCuda
    Enable CUDA support for GPU acceleration

.PARAMETER Clean
    Clean build directories before building
#>

[CmdletBinding()]
param(
    [ValidateSet('llamacpp', 'mistralrs', 'all')]
    [string]$Backend = 'all',

    [ValidateSet('Debug', 'Release')]
    [string]$Configuration = 'Release',

    [switch]$EnableCuda,
    [switch]$DisableCache,
    [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$ProjectRoot = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ProjectRoot
$ToolsDir = Join-Path $RepoRoot 'Tools'

#region Environment Initialization

function Initialize-BuildEnvironment {
    Write-Host "`nInitializing Build Environment..." -ForegroundColor Cyan

    # 1. Initialize CUDA if requested
    if ($EnableCuda) {
        $cudaHelper = Join-Path $ToolsDir 'Initialize-CudaEnvironment.ps1'
        if (Test-Path $cudaHelper) {
            . $cudaHelper
            $cudaInfo = Initialize-CudaEnvironment -Quiet
            if ($cudaInfo.Found) {
                Write-Host "  CUDA initialized: $($cudaInfo.CudaPath)" -ForegroundColor Green
                $env:LLAMA_CUDA = '1'
                $env:GGML_CUDA = 'ON'

                # Explicitly set CUDA compiler for CMake
                $nvccPath = (Join-Path $cudaInfo.CudaPath 'bin\nvcc.exe') -replace '\\', '/'
                if (Test-Path $nvccPath) {
                    $env:CMAKE_CUDA_COMPILER = $nvccPath
                    Write-Host "    nvcc identified: $nvccPath" -ForegroundColor Green

                    # Set NVCC_CCBIN for candle/mistralrs
                    $clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source -replace '\\', '/'
                    if ($clPath) {
                        $env:NVCC_CCBIN = $clPath
                    }
                }
            } else {
                Write-Host '  CUDA not found, building CPU-only' -ForegroundColor Yellow
                $script:EnableCuda = $false
            }
        }
    }

    # 2. Locate stable CMake
    Write-Host '  Locating stable CMake (VS 3.x)...' -ForegroundColor Cyan
    $vsCmake = 'C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path $vsCmake)) {
        $vsCmake = (Get-Command cmake -ErrorAction SilentlyContinue).Source
    }

    if ($vsCmake) {
        # CRITICAL: Clean up PATH of ANY other CMake-related entries
        $cmakeBin = Split-Path $vsCmake -Parent
        $cleanPath = ($env:PATH -split ';' | Where-Object { $_ -notlike '*CMake*' -and $_ -ne '' }) -join ';'
        $env:PATH = "$cmakeBin;$cleanPath"

        $env:CMAKE = $vsCmake
        $env:CMAKE_COMMAND = $vsCmake
        $env:CMAKE_PROGRAM = $vsCmake
        $env:CMAKE_EXECUTABLE = $vsCmake
        $env:CMAKE_ROOT = Join-Path (Split-Path $cmakeBin -Parent) 'share\cmake-3.31' # Approximate, but usually safer to unset

        Write-Host "  CMake prioritized: $vsCmake" -ForegroundColor Green
        & $vsCmake --version | Select-Object -First 1
    } else {
        throw 'Stable CMake not found'
    }

    # Clear variables that might still pollute CMake
    @('CMAKE_MODULE_PATH', 'CMAKE_TOOLCHAIN_FILE', 'CMAKE_PREFIX_PATH', 'CMAKE_ROOT') | ForEach-Object {
        if (Get-Item "Env:$_" -ErrorAction SilentlyContinue) {
            Write-Host "    Clearing $_" -ForegroundColor Yellow
            Remove-Item "Env:$_" -ErrorAction SilentlyContinue
        }
    }

    # 3. Initialize MSVC and SDK (Clear polluted env vars, set cl.exe and rc.exe)
    $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path $vswhere) {
        $vsPath = & $vswhere -latest -property installationPath
        $devShell = Join-Path $vsPath 'Common7\Tools\Launch-VsDevShell.ps1'
        if (Test-Path $devShell) {
            Write-Host '  Initializing MSVC via Launch-VsDevShell.ps1...' -ForegroundColor Cyan
            & $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64

            # CRITICAL: Clear polluted environment variables IMMEDIATELY
            @('CL', '_CL_', 'LINK', '_LINK_') | ForEach-Object {
                if (Get-Item "Env:$_" -ErrorAction SilentlyContinue) {
                    Write-Host "    Clearing polluted env var: $_" -ForegroundColor Yellow
                    Remove-Item "Env:$_" -ErrorAction SilentlyContinue
                }
            }

            # Set CC/CXX for crates using cc-rs or cmake
            $clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source -replace '\\', '/'
            if ($clPath) {
                $env:CC = $clPath
                $env:CXX = $clPath
                $env:CMAKE_C_COMPILER = $clPath
                $env:CMAKE_CXX_COMPILER = $clPath
                Write-Host "    cl.exe identified: $clPath" -ForegroundColor Green
            }

            # Find Windows SDK rc.exe (required by CMake on Windows)
            $rcPath = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin' -Recurse -Filter 'rc.exe' -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like '*x64*' } |
                Sort-Object { [version]($_.FullName -replace '^.*\\(\d+\.\d+\.\d+\.\d+)\\.*$', '$1') } -Descending |
                Select-Object -First 1 -ExpandProperty FullName
            if ($rcPath) {
                $rcPath = $rcPath -replace '\\', '/'
                $env:CMAKE_RC_COMPILER = $rcPath
                $rcDir = Split-Path $rcPath -Parent
                $env:PATH = "$rcDir;$env:PATH"
                Write-Host "    rc.exe identified: $rcPath" -ForegroundColor Green
            }

            # vcpkg toolchain
            $vcpkgToolchain = Join-Path $vsPath 'VC\vcpkg\scripts\buildsystems\vcpkg.cmake'
            if (Test-Path $vcpkgToolchain) {
                $env:CMAKE_TOOLCHAIN_FILE = $vcpkgToolchain
                Write-Host '    vcpkg toolchain enabled' -ForegroundColor Green
            }
        }
    }

    # 4. Configure Caching and Generator
    if (Get-Command ninja -ErrorAction SilentlyContinue) {
        $env:CMAKE_GENERATOR = 'Ninja'
        $env:CMAKE_MAKE_PROGRAM = (Get-Command ninja.exe).Source
        Write-Host "  Generator: Ninja enabled ($($env:CMAKE_MAKE_PROGRAM))" -ForegroundColor Green
    }

    if (-not $DisableCache -and (Get-Command sccache -ErrorAction SilentlyContinue)) {
        $env:RUSTC_WRAPPER = 'sccache'
        $env:CMAKE_C_COMPILER_LAUNCHER = 'sccache'
        $env:CMAKE_CXX_COMPILER_LAUNCHER = 'sccache'
        # Alignment with mistralrs .cargo/config.toml
        $env:SCCACHE_SERVER_PORT = '4226'
        $env:SCCACHE_CACHE_COMPRESSION = 'zstd'
        $env:SCCACHE_DIRECT = 'true'
        Write-Host '  Caching: sccache enabled' -ForegroundColor Green
    } elseif ($DisableCache) {
        Write-Host '  Caching: explicitly disabled' -ForegroundColor Yellow
        Remove-Item Env:RUSTC_WRAPPER -ErrorAction SilentlyContinue
        Remove-Item Env:CMAKE_C_COMPILER_LAUNCHER -ErrorAction SilentlyContinue
        Remove-Item Env:CMAKE_CXX_COMPILER_LAUNCHER -ErrorAction SilentlyContinue
    }

    # llamacpp specific optimizations
    $env:LLAMA_NO_OPENMP = '1'
    $env:LLAMA_CURL = 'OFF'
    $env:LLAMA_BUILD_TESTS = 'OFF'
    $env:LLAMA_BUILD_EXAMPLES = 'OFF'
    $env:LLAMA_BUILD_TOOLS = 'OFF'
}

function Initialize-LlamaCpp {
    param([string]$Configuration)

    Write-Host "`n=== Pre-configuring llama-cpp-sys-2 CMake ===" -ForegroundColor Cyan
    $targetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $ProjectRoot 'target' }
    $profile = if ($Configuration -eq 'Release') { 'release' } else { 'debug' }
    $buildBase = Join-Path $targetDir "$profile\build"

    if (-not (Test-Path $buildBase)) {
        Write-Host "  Build base not found: $buildBase" -ForegroundColor Yellow
        return
    }

    # Find the llama-cpp-sys-2 directory (hashes change)
    $llamaBuildDirs = Get-ChildItem $buildBase -Filter 'llama-cpp-sys-2-*' -Directory -ErrorAction SilentlyContinue
    if (-not $llamaBuildDirs) {
        Write-Host '  llama-cpp-sys-2 build dir not found yet.' -ForegroundColor Yellow
        return
    }

    foreach ($dir in $llamaBuildDirs) {
        $outDir = Join-Path $dir.FullName 'out'
        $cmakeBuildDir = Join-Path $outDir 'build'

        # We need the source directory. Cargo usually puts it in $HOME/.cargo/registry/src/...
        # But we can try to guess it from the build script or use the T:\ path if on user's system
        $cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $env:USERPROFILE '.cargo' }
        $registrySrc = Join-Path $cargoHome 'registry\src\index.crates.io-*'

        $llamaSrcRoot = Get-ChildItem $registrySrc -Filter 'llama-cpp-sys-2-*' -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $llamaSrcRoot) {
            Write-Host '  Could not find llama-cpp-sys-2 source in registry.' -ForegroundColor Yellow
            continue
        }
        $llamaSrcDir = (Join-Path $llamaSrcRoot.FullName 'llama.cpp') -replace '\\', '/'

        Write-Host "  Found llama.cpp source: $llamaSrcDir" -ForegroundColor Gray
        $cmakeBuildDir = $cmakeBuildDir -replace '\\', '/'
        Write-Host "  Configuring in: $cmakeBuildDir" -ForegroundColor Gray

        if (-not (Test-Path $cmakeBuildDir)) { New-Item -ItemType Directory -Path $cmakeBuildDir -Force | Out-Null }

        $clPath = (Get-Command cl.exe -ErrorAction SilentlyContinue).Source
        $ninjaPath = (Get-Command ninja.exe -ErrorAction SilentlyContinue).Source
        $rcPath = $env:CMAKE_RC_COMPILER

        $cmakeArgs = @(
            '-S', $llamaSrcDir,
            '-B', $cmakeBuildDir,
            '-G', 'Ninja',
            "-DCMAKE_MAKE_PROGRAM=$ninjaPath",
            "-DCMAKE_C_COMPILER=$clPath",
            "-DCMAKE_CXX_COMPILER=$clPath",
            "-DCMAKE_RC_COMPILER=$rcPath",
            "-DCMAKE_BUILD_TYPE=$Configuration",
            "-DCMAKE_INSTALL_PREFIX=$outDir",
            '-DGGML_CUDA=ON',
            '-DLLAMA_CURL=OFF',
            '-DLLAMA_BUILD_TESTS=OFF',
            '-DLLAMA_BUILD_EXAMPLES=OFF',
            '-DLLAMA_BUILD_TOOLS=OFF',
            '-DBUILD_SHARED_LIBS=ON'
        )

        if ($EnableCuda) {
            $cudaPath = $env:CUDA_PATH -replace '\\', '/'
            $nvccPath = "$cudaPath/bin/nvcc.exe"
            if (Test-Path $nvccPath) {
                $cmakeArgs += "-DCMAKE_CUDA_COMPILER=$nvccPath"
            }
        }

        & $env:CMAKE @cmakeArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  CMake pre-config failed for $dir" -ForegroundColor Red
        } else {
            Write-Host "  CMake pre-config SUCCESS for $dir" -ForegroundColor Green
        }
    }
}

function Clear-IncompleteCmakeConfig {
    Write-Host 'Checking for incomplete CMake configurations (Nuclear Evasion)...' -ForegroundColor DarkCyan
    $targetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { Join-Path $ProjectRoot 'target' }
    if (-not (Test-Path $targetDir)) { return }

    # Targeted cleaning for troublesome crates
    Write-Host '  Selective cleaning for candle and llama-cpp...' -ForegroundColor Cyan
    $llamaBuildDirs = Get-ChildItem $targetDir -Recurse -Filter 'llama-cpp-sys-2-*' -Directory -ErrorAction SilentlyContinue
    $candleBuildDirs = Get-ChildItem $targetDir -Recurse -Filter 'candle-core-*' -Directory -ErrorAction SilentlyContinue
    foreach ($dir in ($llamaBuildDirs + $candleBuildDirs)) {
        $outDir = Join-Path $dir.FullName 'out'
        $cmakeBuildDir = Join-Path $outDir 'build'
        $cacheFile = Join-Path $cmakeBuildDir 'CMakeCache.txt'
        $ninjaFile = Join-Path $cmakeBuildDir 'build.ninja'
        if ((Test-Path $cacheFile) -and -not (Test-Path $ninjaFile)) {
            Write-Host "    Cleaning incomplete config: $dir" -ForegroundColor Yellow
            Remove-Item $outDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Get-ChildItem $targetDir -Recurse -Filter 'CMakeCache.txt' -ErrorAction SilentlyContinue | ForEach-Object {
        $dir = $_.DirectoryName
        $ninjaFile = Join-Path $dir 'build.ninja'
        if (-not (Test-Path $ninjaFile)) {
            Write-Host "    Cleaning incomplete config in: $dir" -ForegroundColor Yellow
            Remove-Item (Split-Path $dir -Parent) -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    <# Aggressive cleaning for ALL CMake-based crates - DISABLED: Wipes bindings.rs
    Write-Host '  Aggressive cleaning for ALL CMake-based crates...' -ForegroundColor Cyan
    if (Test-Path $targetDir) {
        Get-ChildItem $targetDir -Recurse -Filter 'CMakeCache.txt' -ErrorAction SilentlyContinue | ForEach-Object {
            $parentDir = Split-Path $_.DirectoryName -Parent # This should be the 'out' directory
            Write-Host "    Wiping: $parentDir" -ForegroundColor Yellow
            Remove-Item $parentDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    #>
}

#endregion

#region Build Logic

function Invoke-Build {
    param([string]$BackendName)

    Write-Host "`n=== Building Backend: $BackendName ($Configuration) ===" -ForegroundColor Magenta

    $features = @('ffi', 'server')
    if ($BackendName -eq 'llamacpp' -or $BackendName -eq 'all') { $features += 'llamacpp' }
    if ($BackendName -eq 'mistralrs' -or $BackendName -eq 'all') { $features += 'mistralrs-backend' }
    if ($EnableCuda) { $features += 'cuda' }

    $featureString = ($features | Select-Object -Unique) -join ','
    Write-Host "  Features: $featureString" -ForegroundColor Cyan

    $cargoArgs = @('build', '--features', $featureString, '--message-format=json')
    if ($Configuration -eq 'Release') { $cargoArgs += '--release' }

    $env:RUST_BACKTRACE = 'full'
    Write-Host '  Verifying environment before build...' -ForegroundColor Gray
    & cmake --version | Select-Object -First 1
    & cl.exe 2>&1 | Select-Object -First 1

    Push-Location $ProjectRoot
    $startTime = Get-Date

    try {
        Write-Host "  Executing: cargo $($cargoArgs -join ' ')" -ForegroundColor Gray

        $process = Start-Process -FilePath 'cargo.exe' -ArgumentList $cargoArgs -NoNewWindow -PassThru -RedirectStandardOutput 'cargo_stdout.json' -RedirectStandardError 'cargo_stderr.log'

        $lastPkg = ''
        while (-not $process.HasExited) {
            if (Test-Path 'cargo_stdout.json') {
                try {
                    # Tail the output file to get the latest compiler artifacts
                    $lines = Get-Content 'cargo_stdout.json' -Tail 5 -ErrorAction SilentlyContinue
                    foreach ($line in $lines) {
                        if ($line -match '"reason":"compiler-artifact"') {
                            $msg = $line | ConvertFrom-Json -ErrorAction SilentlyContinue
                            if ($msg -and $msg.package_id) {
                                $pkg = $msg.package_id.Split(' ')[0]
                                if ($pkg -ne $lastPkg) {
                                    Write-Progress -Activity "Building $BackendName" -Status "Compiling: $pkg"
                                    $lastPkg = $pkg
                                }
                            }
                        }
                    }
                } catch {}
            }
            Start-Sleep -Seconds 1
        }

        if ($process.ExitCode -ne 0) {
            Write-Host "`nBuild FAILED with Exit Code: $($process.ExitCode)" -ForegroundColor Red
            if (Test-Path 'cargo_stderr.log') {
                Write-Host "`n--- Tail of Error Log ---" -ForegroundColor Red
                Get-Content 'cargo_stderr.log' -Tail 20
            }

            # Diagnostic for -1 (Crash)
            if ($process.ExitCode -eq -1 -or $process.ExitCode -gt 128) {
                Write-Host "`nCRITICAL: Build process crashed or timed out. Check system memory and disk locks." -ForegroundColor Yellow
            }

            throw "Build failed for $BackendName"
        }
    } finally {
        $duration = (Get-Date) - $startTime
        Write-Host ('  Duration: {0:n2}s' -f $duration.TotalSeconds) -ForegroundColor Gray
        Pop-Location
    }
}

#endregion

# Main Execution
if ($Clean) {
    Write-Host 'Cleaning target directory...' -ForegroundColor Yellow
    if (Test-Path (Join-Path $ProjectRoot 'target')) { Remove-Item (Join-Path $ProjectRoot 'target') -Recurse -Force }
}

Initialize-BuildEnvironment
Clear-IncompleteCmakeConfig
# Initialize-LlamaCpp -Configuration $Configuration

if ($Backend -eq 'all') {
    Invoke-Build -BackendName 'all'
} else {
    Invoke-Build -BackendName $Backend
}

Write-Host "`nBuild Complete!" -ForegroundColor Green
