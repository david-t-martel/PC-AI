#Requires -Version 5.1
<#
.SYNOPSIS
Tests the CargoTools module rust-analyzer integration.
#>

[CmdletBinding()]
param()

Write-Host '=== CargoTools Module Test ===' -ForegroundColor Cyan
Write-Host ''

# Force reimport using full path
$modulePath = Join-Path $env:USERPROFILE 'OneDrive\Documents\PowerShell\Modules\CargoTools\CargoTools.psd1'
Remove-Module CargoTools -Force -ErrorAction SilentlyContinue
Import-Module $modulePath -Force

# Test functions exist
Write-Host '=== Rust-Analyzer Functions ===' -ForegroundColor Yellow
Get-Command -Module CargoTools | Where-Object { $_.Name -like '*RustAnalyzer*' } |
    Format-Table Name, CommandType -AutoSize

# Test Resolve-RustAnalyzerPath
Write-Host '=== Testing Resolve-RustAnalyzerPath ===' -ForegroundColor Yellow
$raPath = Resolve-RustAnalyzerPath
Write-Host "Resolved path: $raPath"
if ($raPath -and (Test-Path $raPath)) {
    $info = Get-Item $raPath
    Write-Host "File size: $([math]::Round($info.Length/1MB,2))MB" -ForegroundColor Green
    Write-Host "Version check:" -ForegroundColor Gray
    & $raPath --version
} else {
    Write-Host 'ERROR: rust-analyzer not found!' -ForegroundColor Red
}

Write-Host ''

# Test shim exists
Write-Host '=== Testing Shim ===' -ForegroundColor Yellow
$shimPath = 'C:\Users\david\bin\rust-analyzer.cmd'
if (Test-Path $shimPath) {
    Write-Host "Shim exists: $shimPath" -ForegroundColor Green
    $resolved = Get-Command rust-analyzer -ErrorAction SilentlyContinue
    if ($resolved) {
        Write-Host "PATH resolution: $($resolved.Source)"
        if ($resolved.Source -like '*.cmd') {
            Write-Host 'Shim has PATH priority!' -ForegroundColor Green
        } else {
            Write-Host 'WARNING: Shim does not have PATH priority' -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "Shim missing: $shimPath" -ForegroundColor Red
}

Write-Host ''

# Run health check
Write-Host '=== Running Test-RustAnalyzerHealth ===' -ForegroundColor Yellow
$health = Test-RustAnalyzerHealth
Write-Host ''
Write-Host "Final Status: $($health.Status)" -ForegroundColor $(
    switch ($health.Status) {
        'Healthy' { 'Green' }
        'NotRunning' { 'Gray' }
        'HighMemory' { 'Yellow' }
        'MultipleInstances' { 'Red' }
        default { 'White' }
    }
)

Write-Host ''
Write-Host '=== Test Complete ===' -ForegroundColor Cyan
