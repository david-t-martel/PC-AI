#Requires -Version 5.1
# Test CMake configuration manually

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$toolsDir = Join-Path $repoRoot 'Tools'
$cacheHelper = Join-Path $toolsDir 'Initialize-CacheEnvironment.ps1'
if (Test-Path $cacheHelper) {
    . $cacheHelper
    Initialize-CacheEnvironment -Quiet | Out-Null
}
$cmakeHelper = Join-Path $toolsDir 'Initialize-CmakeEnvironment.ps1'
if (Test-Path $cmakeHelper) {
    . $cmakeHelper
    Initialize-CmakeEnvironment -Quiet | Out-Null
}

# Setup MSVC
Write-Host "Setting up MSVC environment..."
& "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1" -SkipAutomaticLocation -HostArch amd64 -Arch amd64

# For Visual Studio generator, don't set CC/CXX - it uses vcvarsall internally
$clPath = (Get-Command cl.exe).Source
Write-Host "cl.exe found at: $clPath"

# Clear CC/CXX to let VS generator detect properly
Remove-Item Env:CC -ErrorAction SilentlyContinue
Remove-Item Env:CXX -ErrorAction SilentlyContinue

# Paths
$sourceDir = "T:\RustCache\cargo-home\registry\src\index.crates.io-1949cf8c6b5b557f\llama-cpp-sys-2-0.1.132\llama.cpp"
$buildDir = "T:\test-cmake-build"
$installDir = "T:\test-cmake-install"

# Clean and create
Write-Host "Cleaning test directories..."
Remove-Item $buildDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $buildDir -Force | Out-Null

Write-Host ""
Write-Host "Source dir: $sourceDir"
Write-Host "Build dir: $buildDir"
Write-Host "Install dir: $installDir"
Write-Host ""

# Check if source exists
if (-not (Test-Path $sourceDir)) {
    Write-Host "Source directory not found!" -ForegroundColor Red
    exit 1
}

# Use Visual Studio generator with vcpkg toolchain
$vcpkgRoot = "C:\codedev\vcpkg"
$toolchainFile = Join-Path $vcpkgRoot "scripts\buildsystems\vcpkg.cmake"

Write-Host "Running CMake configure with Visual Studio generator..."
Write-Host "Toolchain: $toolchainFile"
cmake -G "Visual Studio 17 2022" -A x64 -S $sourceDir -B $buildDir -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$installDir -DCMAKE_TOOLCHAIN_FILE="$toolchainFile"

Write-Host ""
Write-Host "CMake exit code: $LASTEXITCODE"
Write-Host ""

Write-Host "Checking for build files..."
$slnFiles = Get-ChildItem $buildDir -Filter "*.sln" -ErrorAction SilentlyContinue
if ($slnFiles) {
    Write-Host "Solution file found: $($slnFiles.Name)" -ForegroundColor Green
    Write-Host ""
    Write-Host "Building..."
    cmake --build $buildDir --config Release --parallel 4
    Write-Host "Build exit code: $LASTEXITCODE"
} else {
    Write-Host "No solution file found" -ForegroundColor Red
    Write-Host "Directory contents:"
    Get-ChildItem $buildDir | ForEach-Object { Write-Host "  $_" }
}
