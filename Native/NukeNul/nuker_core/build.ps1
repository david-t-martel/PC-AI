#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Build script for nuker_core.dll

.DESCRIPTION
    Automates building the Rust DLL with various profiles and configurations.
    Handles copying the DLL to convenient locations and running tests.

.PARAMETER Profile
    Build profile: debug, release, or release-memory-optimized

.PARAMETER Test
    Run tests after building

.PARAMETER Copy
    Copy DLL to parent directory after successful build

.PARAMETER Clean
    Clean build artifacts before building

.PARAMETER NativeOptimize
    Enable CPU-specific optimizations (not portable!)

.EXAMPLE
    .\build.ps1 -Profile release
    Builds release version

.EXAMPLE
    .\build.ps1 -Profile release -Test -Copy
    Builds, tests, and copies DLL to parent directory

.EXAMPLE
    .\build.ps1 -Clean -Profile release -NativeOptimize
    Clean build with native CPU optimizations
#>

param(
    [Parameter()]
    [ValidateSet('debug', 'release', 'release-memory-optimized')]
    [string]$Profile = 'release',

    [Parameter()]
    [switch]$Test,

    [Parameter()]
    [switch]$Copy,

    [Parameter()]
    [switch]$Clean,

    [Parameter()]
    [switch]$NativeOptimize
)

# Color output functions
function Write-Success($msg) {
    Write-Host "✓ $msg" -ForegroundColor Green
}

function Write-Error($msg) {
    Write-Host "✗ $msg" -ForegroundColor Red
}

function Write-Info($msg) {
    Write-Host "ℹ $msg" -ForegroundColor Cyan
}

function Write-Warning($msg) {
    Write-Host "⚠ $msg" -ForegroundColor Yellow
}

# Header
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Nuker Core DLL Build Script" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify we're in the right directory
if (-not (Test-Path "Cargo.toml")) {
    Write-Error "Cargo.toml not found. Run this script from the nuker_core directory."
    exit 1
}

# Check Rust installation
Write-Info "Checking Rust installation..."
try {
    $rustVersion = rustc --version 2>&1
    $cargoVersion = cargo --version 2>&1
    Write-Success "Rust: $rustVersion"
    Write-Success "Cargo: $cargoVersion"
} catch {
    Write-Error "Rust not found. Install from: https://rustup.rs"
    exit 1
}

# Clean if requested
if ($Clean) {
    Write-Info "Cleaning build artifacts..."
    cargo clean
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Clean complete"
    } else {
        Write-Error "Clean failed"
        exit 1
    }
}

# Set RUSTFLAGS for native optimization if requested
if ($NativeOptimize) {
    Write-Warning "Enabling native CPU optimizations (binary will not be portable!)"
    $env:RUSTFLAGS = "-C target-cpu=native"
}

# Build
Write-Info "Building with profile: $Profile"
$buildStart = Get-Date

if ($Profile -eq 'debug') {
    cargo build
} else {
    cargo build --profile $Profile
}

$buildTime = (Get-Date) - $buildStart

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

Write-Success "Build completed in $([math]::Round($buildTime.TotalSeconds, 2)) seconds"

# Determine DLL path
$dllPath = if ($Profile -eq 'debug') {
    "target\debug\nuker_core.dll"
} else {
    "target\$Profile\nuker_core.dll"
}

# Check if DLL exists
if (-not (Test-Path $dllPath)) {
    Write-Error "DLL not found at: $dllPath"
    exit 1
}

# Get DLL size
$dllSize = (Get-Item $dllPath).Length
$dllSizeKB = [math]::Round($dllSize / 1KB, 2)
Write-Info "DLL size: $dllSizeKB KB"
Write-Info "DLL location: $dllPath"

# Run tests if requested
if ($Test) {
    Write-Info "`nRunning tests..."
    cargo test -- --nocapture
    if ($LASTEXITCODE -eq 0) {
        Write-Success "All tests passed"
    } else {
        Write-Error "Tests failed"
        exit 1
    }
}

# Copy DLL if requested
if ($Copy) {
    Write-Info "`nCopying DLL to parent directory..."
    $destPath = "..\nuker_core.dll"
    Copy-Item $dllPath $destPath -Force
    if ($?) {
        Write-Success "DLL copied to: $destPath"
    } else {
        Write-Error "Failed to copy DLL"
        exit 1
    }
}

# Verify DLL exports
Write-Info "`nVerifying DLL exports..."
try {
    $exports = dumpbin /EXPORTS $dllPath 2>&1 | Select-String -Pattern "nuke_reserved_files|nuker_core"
    if ($exports) {
        Write-Success "Found exported functions:"
        $exports | ForEach-Object { Write-Host "  - $_" -ForegroundColor Gray }
    } else {
        Write-Warning "Could not verify exports (dumpbin not found or failed)"
    }
} catch {
    Write-Warning "Could not verify exports (dumpbin not available)"
}

# Test DLL loading
Write-Info "`nTesting DLL loading..."
try {
    Add-Type @"
using System;
using System.Runtime.InteropServices;

public class NukerTest {
    [DllImport("$($dllPath -replace '\\', '\\\\')", CallingConvention = CallingConvention.Cdecl)]
    public static extern uint nuker_core_test();
}
"@

    $result = [NukerTest]::nuker_core_test()
    if ($result -eq 0xDEADBEEF) {
        Write-Success "DLL loaded and test function executed successfully!"
    } else {
        Write-Error "DLL test function returned unexpected value: 0x$($result.ToString('X'))"
    }
} catch {
    Write-Warning "Could not test DLL loading: $_"
}

# Final summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  Build Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Profile:     $Profile" -ForegroundColor White
Write-Host "DLL Path:    $dllPath" -ForegroundColor White
Write-Host "DLL Size:    $dllSizeKB KB" -ForegroundColor White
Write-Host "Build Time:  $([math]::Round($buildTime.TotalSeconds, 2))s" -ForegroundColor White
if ($Test) {
    Write-Host "Tests:       Passed" -ForegroundColor Green
}
if ($Copy) {
    Write-Host "Copied:      Yes" -ForegroundColor Green
}
Write-Host "========================================`n" -ForegroundColor Cyan

Write-Success "Build complete!"
