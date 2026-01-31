#Requires -Version 5.1
# Clean llamacpp build with sccache disabled

$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot

Write-Host "=== Cleaning all caches ===" -ForegroundColor Cyan

# Disable sccache
$env:RUSTC_WRAPPER = ""

# Full cargo clean
Write-Host "Running cargo clean..."
cargo clean

# Clean any remaining llama directories
Remove-Item "T:\RustCache\cargo-target\release\build\*llama*" -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== Setting up MSVC environment ===" -ForegroundColor Cyan

$devShell = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1"
& $devShell -SkipAutomaticLocation -HostArch amd64 -Arch amd64

$clPath = (Get-Command cl.exe).Source
Write-Host "cl.exe: $clPath"

# Use VS Ninja from Visual Studio installation
$vsNinja = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe"
if (Test-Path $vsNinja) {
    $ninjaPath = $vsNinja
} else {
    $ninjaPath = "C:\Users\david\.local\bin\ninja.exe"
}
Write-Host "ninja: $ninjaPath"

# Set environment variables
$env:CC = $clPath
$env:CXX = $clPath
$env:CMAKE_C_COMPILER = $clPath
$env:CMAKE_CXX_COMPILER = $clPath
$env:CMAKE_GENERATOR = "Ninja"
$env:CMAKE_MAKE_PROGRAM = $ninjaPath
$env:LLAMA_CUDA = "0"

Write-Host ""
Write-Host "=== Building llamacpp backend (no sccache) ===" -ForegroundColor Cyan
Write-Host "CMAKE_GENERATOR: $env:CMAKE_GENERATOR"
Write-Host "CMAKE_MAKE_PROGRAM: $env:CMAKE_MAKE_PROGRAM"
Write-Host "RUSTC_WRAPPER: (disabled)"
Write-Host ""

# Run cargo build without sccache
cargo build --features llamacpp,ffi,server --lib --release

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "=== BUILD SUCCESSFUL ===" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=== BUILD FAILED (exit code: $LASTEXITCODE) ===" -ForegroundColor Red
    exit $LASTEXITCODE
}
