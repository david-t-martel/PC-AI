#Requires -Modules Pester
<#
.SYNOPSIS
Runs Pester tests for CargoTools module.
#>

[CmdletBinding()]
param(
    [switch]$Detailed
)

$testPath = Join-Path $env:USERPROFILE 'OneDrive\Documents\PowerShell\Modules\CargoTools\Tests\Invoke-RustAnalyzerWrapper.Tests.ps1'

if (-not (Test-Path $testPath)) {
    Write-Error "Test file not found: $testPath"
    exit 1
}

Write-Host 'Running CargoTools Pester Tests' -ForegroundColor Cyan
Write-Host "Test file: $testPath" -ForegroundColor Gray
Write-Host ''

$config = New-PesterConfiguration
$config.Run.Path = $testPath
$config.Output.Verbosity = if ($Detailed) { 'Detailed' } else { 'Normal' }
$config.Run.PassThru = $true

$results = Invoke-Pester -Configuration $config

Write-Host ''
Write-Host '=== Test Summary ===' -ForegroundColor Cyan
Write-Host "Total:   $($results.TotalCount)"
Write-Host "Passed:  $($results.PassedCount)" -ForegroundColor Green
Write-Host "Failed:  $($results.FailedCount)" -ForegroundColor $(if ($results.FailedCount -gt 0) { 'Red' } else { 'Gray' })
Write-Host "Skipped: $($results.SkippedCount)" -ForegroundColor Yellow

exit $results.FailedCount
