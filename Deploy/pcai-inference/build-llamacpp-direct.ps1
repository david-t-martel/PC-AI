#Requires -Version 5.1
# Direct llamacpp build with explicit CMake settings

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "=== Setting up MSVC environment ===" -ForegroundColor Cyan

# Setup MSVC environment
$devShell = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1"
& $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64

# Get cl.exe path
$clPath = (Get-Command cl.exe).Source
Write-Host "cl.exe: $clPath"

# Set ninja path explicitly
$ninjaPath = "C:\Users\david\.local\bin\ninja.exe"
if (-not (Test-Path $ninjaPath)) {
    $ninjaPath = (Get-Command ninja.exe).Source
}
Write-Host "ninja: $ninjaPath"

# CRITICAL: Clear the CL environment variable if it contains a path
# This prevents MSVC from interpreting paths as source files
if ($env:CL -and $env:CL -like '*/*') {
    Write-Host "WARNING: Clearing invalid CL env var: $env:CL" -ForegroundColor Yellow
    Remove-Item Env:CL -ErrorAction SilentlyContinue
}
if ($env:_CL_ -and $env:_CL_ -like '*/*') {
    Write-Host "WARNING: Clearing invalid _CL_ env var: $env:_CL_" -ForegroundColor Yellow
    Remove-Item Env:_CL_ -ErrorAction SilentlyContinue
}

# Set environment variables for CMake
$env:CC = $clPath
$env:CXX = $clPath
$env:CMAKE_C_COMPILER = $clPath
$env:CMAKE_CXX_COMPILER = $clPath
$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKE_MAKE_PROGRAM = $ninjaPath
$env:LLAMA_CUDA = "0"

Write-Host ""
Write-Host "=== Building llamacpp backend ===" -ForegroundColor Cyan
Write-Host "CMAKE_GENERATOR: $env:CMAKE_GENERATOR"
Write-Host "CMAKE_MAKE_PROGRAM: $env:CMAKE_MAKE_PROGRAM"
Write-Host ""

# Run cargo build
cargo build --features llamacpp,ffi,server --lib --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== BUILD SUCCESSFUL ===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== BUILD FAILED (exit code: $LASTEXITCODE) ===" -ForegroundColor Red
    exit $LASTEXITCODE
}
