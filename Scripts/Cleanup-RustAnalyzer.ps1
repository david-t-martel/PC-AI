#Requires -Version 5.1
<#
.SYNOPSIS
Cleans up redundant rust-analyzer installations.
#>

[CmdletBinding()]
param()

Write-Host 'Cleaning up redundant rust-analyzer copies...' -ForegroundColor Cyan

$redundant = @(
    'C:\Users\david\.cargo\bin\rust-analyzer.exe',
    'T:\RustCache\cargo-home\bin\rust-analyzer.exe'
)

foreach ($path in $redundant) {
    if (Test-Path $path) {
        Remove-Item $path -Force
        Write-Host "  Removed: $path" -ForegroundColor Green
    } else {
        Write-Host "  Already gone: $path" -ForegroundColor Gray
    }
}

# Verify canonical path still exists
$canonical = 'T:\RustCache\rustup\toolchains\stable-x86_64-pc-windows-msvc\bin\rust-analyzer.exe'
if (Test-Path $canonical) {
    $info = Get-Item $canonical
    Write-Host "Canonical rust-analyzer preserved: $canonical ($([math]::Round($info.Length/1MB,2))MB)" -ForegroundColor Green
}

# Run final health check
Write-Host ''
Write-Host 'Final health check:' -ForegroundColor Cyan
$modulePath = Join-Path $env:USERPROFILE 'OneDrive\Documents\PowerShell\Modules\CargoTools\CargoTools.psd1'
Import-Module $modulePath -Force
$health = Test-RustAnalyzerHealth -Quiet
Write-Host "Status: $($health.Status)"
Write-Host "Processes: $($health.ProcessCount)"
Write-Host "Memory: $($health.MemoryMB)MB"
Write-Host "Shim installed: $($health.ShimExists)"
Write-Host "Shim priority: $($health.ShimPriority)"
