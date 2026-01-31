#Requires -Version 5.1
<#
.SYNOPSIS
    Direct llamacpp build with explicit MSVC configuration (no ENV VAR fallbacks)

.DESCRIPTION
    This script builds the llamacpp backend with all necessary fixes:
    - Clears polluted environment variables (CL, _CL_, etc.)
    - Sets explicit paths to cl.exe and ninja.exe
    - Cleans stale CMake configurations
    - Tests cl.exe before building
#>

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "=== MSVC Environment Setup (No Fallbacks) ===" -ForegroundColor Cyan

# Setup MSVC environment
$devShell = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1"
if (-not (Test-Path $devShell)) {
    throw "Visual Studio 2022 not found at expected path"
}
& $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64

# CRITICAL: Clear polluted environment variables IMMEDIATELY
# These can corrupt MSVC command line parsing
Write-Host "`nClearing polluted environment variables..." -ForegroundColor Yellow
@('CL', '_CL_', 'LINK', '_LINK_') | ForEach-Object {
    if (Get-Item "Env:$_" -ErrorAction SilentlyContinue) {
        $val = (Get-Item "Env:$_").Value
        Write-Host "  Clearing $_=$val"
        Remove-Item "Env:$_" -ErrorAction SilentlyContinue
    }
}

# Get cl.exe ABSOLUTE path
$clPath = (Get-Command cl.exe).Source
Write-Host "`ncl.exe: $clPath" -ForegroundColor Green

# Test cl.exe ACTUALLY WORKS
Write-Host "Testing cl.exe..."
$testFile = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.c'
"int main() { return 0; }" | Out-File -FilePath $testFile -Encoding ASCII
$ErrorActionPreference = 'Continue'
$null = & cl.exe /c $testFile /Fo"$env:TEMP\cltest.obj" 2>&1
$clResult = $LASTEXITCODE
$ErrorActionPreference = 'Stop'
Remove-Item $testFile -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\cltest.obj" -ErrorAction SilentlyContinue

if ($clResult -ne 0) {
    throw "cl.exe test FAILED (exit code: $clResult)"
}
Write-Host "cl.exe test PASSED" -ForegroundColor Green

# Find ninja - prefer local installation
$ninjaPath = "$env:USERPROFILE\.local\bin\ninja.exe"
if (-not (Test-Path $ninjaPath)) {
    $ninjaPath = (Get-Command ninja.exe -ErrorAction SilentlyContinue).Source
}
if (-not $ninjaPath) {
    throw "ninja.exe not found"
}
Write-Host "ninja: $ninjaPath" -ForegroundColor Green

# Find Windows SDK rc.exe (resource compiler) - CMake needs this explicitly
Write-Host "`nLocating Windows SDK resource compiler..."
$rcPath = Get-ChildItem "C:\Program Files (x86)\Windows Kits\10\bin" -Recurse -Filter "rc.exe" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*x64*" } |
    Sort-Object { [version]($_.FullName -replace '^.*\\(\d+\.\d+\.\d+\.\d+)\\.*$', '$1') } -Descending |
    Select-Object -First 1 -ExpandProperty FullName
if (-not $rcPath) {
    throw "Windows SDK rc.exe not found"
}
$rcDir = Split-Path $rcPath -Parent
Write-Host "rc.exe: $rcPath" -ForegroundColor Green

# Add Windows SDK to PATH for CMake subprocess
$env:PATH = "$rcDir;$env:PATH"

# Clean ONLY incomplete CMake configurations (CMakeCache.txt without build.ninja)
# Do NOT clean complete configurations - those can be reused
Write-Host ""
Write-Host "=== Checking CMake Configs ===" -ForegroundColor Cyan
$targetDir = if ($env:CARGO_TARGET_DIR) { $env:CARGO_TARGET_DIR } else { 'T:\RustCache\cargo-target' }
foreach ($profile in @('debug', 'release')) {
    $buildDir = Join-Path $targetDir "$profile\build"
    if (Test-Path $buildDir) {
        $llamaBuildDirs = Get-ChildItem $buildDir -Filter 'llama-cpp-sys-2-*' -Directory -ErrorAction SilentlyContinue
        foreach ($dir in $llamaBuildDirs) {
            $outDir = Join-Path $dir.FullName "out"
            $cmakeBuildDir = Join-Path $outDir "build"
            $cacheFile = Join-Path $cmakeBuildDir "CMakeCache.txt"
            $ninjaFile = Join-Path $cmakeBuildDir "build.ninja"

            # Only clean if: CMakeCache.txt exists but build.ninja doesn't (incomplete config)
            if ((Test-Path $cacheFile) -and -not (Test-Path $ninjaFile)) {
                Write-Host "Incomplete config detected (CMakeCache.txt without build.ninja)"
                Write-Host "Removing: $outDir"
                Remove-Item $outDir -Recurse -Force
            } elseif (Test-Path $ninjaFile) {
                Write-Host "Valid config found: $cmakeBuildDir" -ForegroundColor Green
            }
        }
    }
}

# SET ALL COMPILER PATHS EXPLICITLY - NO FALLBACKS
$env:CC = $clPath
$env:CXX = $clPath
$env:CMAKE_C_COMPILER = $clPath
$env:CMAKE_CXX_COMPILER = $clPath
$env:CMAKE_RC_COMPILER = $rcPath
$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKE_MAKE_PROGRAM = $ninjaPath

# vcpkg toolchain for finding dependencies
$vcpkgRoot = "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\vcpkg"
$vcpkgToolchain = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"
if (Test-Path $vcpkgToolchain) {
    $env:CMAKE_TOOLCHAIN_FILE = $vcpkgToolchain
    Write-Host "vcpkg toolchain: $vcpkgToolchain" -ForegroundColor Green
}

# LLAMA.CPP build options - disable features not needed for inference
# These are passed to cmake via cmake-rs
$env:LLAMA_NO_OPENMP = "1"
$env:LLAMA_CURL = "OFF"           # Disable CURL (not needed for local inference)
$env:LLAMA_BUILD_TESTS = "OFF"    # Tests not present in vendored source
$env:LLAMA_BUILD_EXAMPLES = "OFF" # Examples not present in vendored source
$env:LLAMA_BUILD_TOOLS = "OFF"    # Tools not present in vendored source

# Initialize CUDA (enable for GPU acceleration)
$EnableCuda = $true
$cudaHelper = "C:\Users\david\PC_AI\Tools\Initialize-CudaEnvironment.ps1"
if ($EnableCuda -and (Test-Path $cudaHelper)) {
    . $cudaHelper
    $cudaInfo = Initialize-CudaEnvironment
    if ($cudaInfo -and $cudaInfo.Found) {
        $env:LLAMA_CUDA = "1"
        $env:GGML_CUDA = "ON"
        Write-Host "CUDA enabled: $($cudaInfo.CudaPath)" -ForegroundColor Green
    } else {
        $env:LLAMA_CUDA = "0"
        $env:GGML_CUDA = "OFF"
    }
} else {
    $env:LLAMA_CUDA = "0"
    $env:GGML_CUDA = "OFF"
}

Write-Host ""
Write-Host "=== Build Configuration ===" -ForegroundColor Cyan
Write-Host "CC:                  $env:CC"
Write-Host "CXX:                 $env:CXX"
Write-Host "CMAKE_GENERATOR:     $env:CMAKE_GENERATOR"
Write-Host "CMAKE_MAKE_PROGRAM:  $env:CMAKE_MAKE_PROGRAM"
Write-Host "CMAKE_C_COMPILER:    $env:CMAKE_C_COMPILER"
Write-Host "CMAKE_CXX_COMPILER:  $env:CMAKE_CXX_COMPILER"
Write-Host "CMAKE_RC_COMPILER:   $env:CMAKE_RC_COMPILER"
Write-Host "CMAKE_TOOLCHAIN:     $env:CMAKE_TOOLCHAIN_FILE"
Write-Host "LLAMA_CUDA:          $env:LLAMA_CUDA"
Write-Host "LLAMA_CURL:          $env:LLAMA_CURL"
Write-Host "LLAMA_BUILD_TESTS:   $env:LLAMA_BUILD_TESTS"
Write-Host ""

# Pre-configure CMake for llama-cpp-sys-2 (cmake-rs doesn't pass our env vars properly)
Write-Host "=== Pre-configuring llama.cpp CMake ===" -ForegroundColor Cyan
$llamaSrcDir = "T:/RustCache/cargo-home/registry/src/index.crates.io-1949cf8c6b5b557f/llama-cpp-sys-2-0.1.132/llama.cpp"
$llamaBuildDir = "T:/RustCache/cargo-target/release/build/llama-cpp-sys-2-e20edaae6dc5d795/out/build"
$llamaInstallDir = "T:/RustCache/cargo-target/release/build/llama-cpp-sys-2-e20edaae6dc5d795/out"

# Check if valid CMake config already exists
$ninjaFile = Join-Path $llamaBuildDir "build.ninja"
if (-not (Test-Path $ninjaFile)) {
    Write-Host "Running CMake configure..."
    Remove-Item $llamaBuildDir -Recurse -Force -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Path $llamaBuildDir -Force | Out-Null

    $cmakeArgs = @(
        "-S", $llamaSrcDir,
        "-B", $llamaBuildDir,
        "-G", "Ninja",
        "-DCMAKE_MAKE_PROGRAM=$ninjaPath",
        "-DCMAKE_C_COMPILER=$clPath",
        "-DCMAKE_CXX_COMPILER=$clPath",
        "-DCMAKE_BUILD_TYPE=Release",
        "-DCMAKE_INSTALL_PREFIX=$llamaInstallDir",
        "-DGGML_CUDA=ON",
        "-DCMAKE_CUDA_COMPILER=C:/Program Files/NVIDIA GPU Computing Toolkit/CUDA/v12.9/bin/nvcc.exe",
        "-DLLAMA_CURL=OFF",
        "-DLLAMA_BUILD_TESTS=OFF",
        "-DLLAMA_BUILD_EXAMPLES=OFF",
        "-DLLAMA_BUILD_TOOLS=OFF",
        "-DBUILD_SHARED_LIBS=ON"
    )

    & cmake @cmakeArgs
    if ($LASTEXITCODE -ne 0) {
        throw "CMake configure failed"
    }
    Write-Host "CMake configure complete" -ForegroundColor Green
} else {
    Write-Host "Using existing CMake configuration" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== Building llamacpp backend with CUDA ===" -ForegroundColor Cyan
# Include cuda feature for GPU acceleration
cargo build --features llamacpp,ffi,server,cuda --lib --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== BUILD SUCCESSFUL ===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== BUILD FAILED (exit code: $LASTEXITCODE) ===" -ForegroundColor Red
    exit $LASTEXITCODE
}
