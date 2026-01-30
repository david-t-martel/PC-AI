<#
.SYNOPSIS
    Generates test coverage report for PC_AI project.

.PARAMETER OutputPath
    Path for the markdown report. Default: Reports/COVERAGE_REPORT.md

.PARAMETER RunTests
    Actually run the tests (slower). Default: just count test files.

.EXAMPLE
    .\Tests\coverage-report.ps1
    .\Tests\coverage-report.ps1 -RunTests
#>
param(
    [string]$OutputPath = (Join-Path $PSScriptRoot '..\Reports\COVERAGE_REPORT.md'),
    [switch]$RunTests
)

$ErrorActionPreference = 'Stop'
$projectRoot = Resolve-Path (Join-Path $PSScriptRoot '..')

# Count test files
$testFiles = Get-ChildItem -Path (Join-Path $projectRoot 'Tests') -Filter '*.Tests.ps1' -Recurse
$unitTests = $testFiles | Where-Object { $_.FullName -match '\\Unit\\' }
$integrationTests = $testFiles | Where-Object { $_.FullName -match '\\Integration\\' }

# Count modules and functions
$modules = Get-ChildItem -Path (Join-Path $projectRoot 'Modules') -Filter '*.psd1' -Recurse |
    Where-Object { $_.FullName -notmatch '\\bin\\' -and $_.Directory.Name -match '^PC-AI\.' }
$publicFunctions = Get-ChildItem -Path (Join-Path $projectRoot 'Modules') -Filter '*.ps1' -Recurse |
    Where-Object { $_.FullName -match '\\Public\\' }

# Count Rust test files
$rustTests = Get-ChildItem -Path $projectRoot -Filter '*.rs' -Recurse |
    Where-Object { $_.FullName -match '\\tests\\' -or $_.Name -match '_test\.rs$' }

# Initialize results
$testResults = $null
if ($RunTests) {
    Write-Host "Running Pester tests..." -ForegroundColor Cyan
    $pesterConfig = New-PesterConfiguration
    $pesterConfig.Run.Path = Join-Path $projectRoot 'Tests'
    $pesterConfig.Run.PassThru = $true
    $pesterConfig.Output.Verbosity = 'Minimal'
    $testResults = Invoke-Pester -Configuration $pesterConfig
}

# Calculate module coverage
$moduleCoverage = $modules | ForEach-Object {
    $moduleName = $_.BaseName
    $moduleTests = $testFiles | Where-Object { $_.Name -match $moduleName }
    [PSCustomObject]@{
        Module = $moduleName
        TestFiles = $moduleTests.Count
    }
} | Sort-Object Module

# Generate report
$report = @"
# PC_AI Test Coverage Report

Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm')

## Summary

| Metric | Count |
|--------|-------|
| PowerShell Modules | $($modules.Count) |
| Public Functions | $($publicFunctions.Count) |
| Unit Test Files | $($unitTests.Count) |
| Integration Test Files | $($integrationTests.Count) |
| Rust Test Files | $($rustTests.Count) |
| Total Test Files | $($testFiles.Count + $rustTests.Count) |

## PowerShell Test Coverage by Module

| Module | Test Files |
|--------|------------|
$($moduleCoverage | ForEach-Object { "| $($_.Module) | $($_.TestFiles) |" } | Out-String)

## Rust Test Coverage

| Crate | Test Files |
|-------|------------|
| rust-functiongemma-runtime | $(@($rustTests | Where-Object { $_.FullName -match 'rust-functiongemma-runtime' }).Count) |
| rust-functiongemma-train | $(@($rustTests | Where-Object { $_.FullName -match 'rust-functiongemma-train' }).Count) |
| pcai_core | $(@($rustTests | Where-Object { $_.FullName -match 'pcai_core' }).Count) |
| pcai_fs | $(@($rustTests | Where-Object { $_.FullName -match 'pcai_fs' }).Count) |

$(if ($testResults) {
@"

## Test Execution Results

| Metric | Value |
|--------|-------|
| Total Tests | $($testResults.TotalCount) |
| Passed | $($testResults.PassedCount) |
| Failed | $($testResults.FailedCount) |
| Skipped | $($testResults.SkippedCount) |
| Pass Rate | $([math]::Round($testResults.PassedCount / [Math]::Max(1, $testResults.TotalCount) * 100, 1))% |
"@
})

## Recommendations

1. Target 85% test coverage for all modules
2. Add integration tests for cross-module functionality
3. Run tests before each commit
"@

# Ensure Reports directory exists
$reportsDir = Split-Path $OutputPath -Parent
if (-not (Test-Path $reportsDir)) {
    New-Item -ItemType Directory -Path $reportsDir -Force | Out-Null
}

Set-Content -Path $OutputPath -Value $report
Write-Host "Coverage report saved to: $OutputPath" -ForegroundColor Green

# Return summary object
[PSCustomObject]@{
    Modules = $modules.Count
    PublicFunctions = $publicFunctions.Count
    UnitTestFiles = $unitTests.Count
    IntegrationTestFiles = $integrationTests.Count
    RustTestFiles = $rustTests.Count
    ReportPath = $OutputPath
}
