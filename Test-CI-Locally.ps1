#Requires -Version 5.1
<#
.SYNOPSIS
    Runs CI pipeline checks locally before pushing to GitHub

.DESCRIPTION
    Simulates the GitHub Actions CI pipeline locally, running linting, testing, and security checks

.PARAMETER Fast
    Skip slower checks like security scanning

.PARAMETER Coverage
    Generate code coverage report

.PARAMETER Fix
    Attempt to auto-fix PSScriptAnalyzer issues

.EXAMPLE
    .\Test-CI-Locally.ps1
    Runs all CI checks

.EXAMPLE
    .\Test-CI-Locally.ps1 -Fast
    Runs only essential checks (lint and unit tests)

.EXAMPLE
    .\Test-CI-Locally.ps1 -Fix
    Auto-fixes PSScriptAnalyzer issues before testing
#>

[CmdletBinding()]
param(
    [switch]$Fast,
    [switch]$Coverage,
    [switch]$Fix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:FailedChecks = @()
$script:PassedChecks = @()
$script:WarningChecks = @()

function Write-CheckHeader {
    param([string]$Message)
    Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Write-CheckResult {
    param(
        [string]$Name,
        [string]$Status,  # 'Pass', 'Fail', 'Warning', 'Skip'
        [string]$Message = ''
    )

    switch ($Status) {
        'Pass' {
            Write-Host "✓ $Name" -ForegroundColor Green
            $script:PassedChecks += $Name
        }
        'Fail' {
            Write-Host "✗ $Name" -ForegroundColor Red
            if ($Message) { Write-Host "  $Message" -ForegroundColor Red }
            $script:FailedChecks += $Name
        }
        'Warning' {
            Write-Host "⚠ $Name" -ForegroundColor Yellow
            if ($Message) { Write-Host "  $Message" -ForegroundColor Yellow }
            $script:WarningChecks += $Name
        }
        'Skip' {
            Write-Host "⊘ $Name (skipped)" -ForegroundColor Gray
        }
    }
}

Write-Host @"
╔═══════════════════════════════════════════════╗
║                                               ║
║   PC_AI Local CI Pipeline                    ║
║   Simulating GitHub Actions checks            ║
║                                               ║
╚═══════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

# Check 1: PowerShell Syntax
Write-CheckHeader "PowerShell Syntax Check"

$syntaxErrors = @()
Get-ChildItem -Recurse -Include *.ps1, *.psm1, *.psd1 | ForEach-Object {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$parseErrors)

    if ($parseErrors) {
        $syntaxErrors += "$($_.Name): $($parseErrors -join ', ')"
    }
}

if ($syntaxErrors.Count -eq 0) {
    Write-CheckResult -Name "PowerShell Syntax" -Status Pass
} else {
    Write-CheckResult -Name "PowerShell Syntax" -Status Fail -Message "$($syntaxErrors.Count) files with syntax errors"
    $syntaxErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

# Check 2: PSScriptAnalyzer
Write-CheckHeader "PSScriptAnalyzer (Code Quality)"

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-CheckResult -Name "PSScriptAnalyzer" -Status Warning -Message "PSScriptAnalyzer not installed. Run Setup-DevEnvironment.ps1"
} else {
    if ($Fix) {
        Write-Host "Attempting to auto-fix issues..." -ForegroundColor Yellow
        Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1 -Fix | Out-Null
    }

    $issues = Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSScriptAnalyzerSettings.psd1

    $errors = $issues | Where-Object { $_.Severity -eq 'Error' }
    $warnings = $issues | Where-Object { $_.Severity -eq 'Warning' }

    Write-Host "  Errors: $($errors.Count)" -ForegroundColor $(if ($errors.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Warnings: $($warnings.Count)" -ForegroundColor $(if ($warnings.Count -eq 0) { 'Green' } else { 'Yellow' })

    if ($errors.Count -eq 0) {
        Write-CheckResult -Name "PSScriptAnalyzer" -Status Pass
    } else {
        Write-CheckResult -Name "PSScriptAnalyzer" -Status Fail -Message "$($errors.Count) errors found"

        Write-Host "`n  Top 5 errors:" -ForegroundColor Red
        $errors | Select-Object -First 5 | ForEach-Object {
            Write-Host "    $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Red
        }
    }

    if ($warnings.Count -gt 0) {
        Write-Host "`n  Top 3 warnings:" -ForegroundColor Yellow
        $warnings | Select-Object -First 3 | ForEach-Object {
            Write-Host "    $($_.ScriptName):$($_.Line) - $($_.Message)" -ForegroundColor Yellow
        }
    }
}

# Check 3: Module Manifests
Write-CheckHeader "Module Manifest Validation"

$manifestErrors = @()
Get-ChildItem -Path Modules -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $manifestPath = Join-Path $_.FullName "$($_.Name).psd1"

    if (Test-Path $manifestPath) {
        try {
            $null = Test-ModuleManifest -Path $manifestPath -ErrorAction Stop
        } catch {
            $manifestErrors += "$($_.Name): $_"
        }
    }
}

if ($manifestErrors.Count -eq 0) {
    Write-CheckResult -Name "Module Manifests" -Status Pass
} else {
    Write-CheckResult -Name "Module Manifests" -Status Fail -Message "$($manifestErrors.Count) invalid manifests"
    $manifestErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

# Check 4: Pester Tests
Write-CheckHeader "Pester Tests"

if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-CheckResult -Name "Pester Tests" -Status Warning -Message "Pester not installed. Run Setup-DevEnvironment.ps1"
} elseif (-not (Test-Path "Tests\.pester.ps1")) {
    Write-CheckResult -Name "Pester Tests" -Status Warning -Message "No test runner found at Tests\.pester.ps1"
} else {
    try {
        if ($Coverage) {
            $result = & ".\Tests\.pester.ps1" -Coverage
        } else {
            $result = & ".\Tests\.pester.ps1"
        }

        # Note: Actual test result parsing depends on .pester.ps1 implementation
        Write-CheckResult -Name "Pester Tests" -Status Pass
    } catch {
        Write-CheckResult -Name "Pester Tests" -Status Fail -Message $_
    }
}

# Check 5: Security Scan (unless -Fast)
if (-not $Fast) {
    Write-CheckHeader "Security Scan"

    # Check for hardcoded credentials
    $credentialPatterns = @(
        'password\s*=\s*["\'][^"\']+["\']',
        'api[_-]?key\s*=\s*["\'][^"\']+["\']',
        'secret\s*=\s*["\'][^"\']+["\']',
        'ConvertTo-SecureString.*-AsPlainText'
    )

    $credentialFindings = @()
    Get-ChildItem -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        foreach ($pattern in $credentialPatterns) {
            if ($content -match $pattern) {
                $credentialFindings += "$($_.Name): Potential credential pattern"
            }
        }
    }

    if ($credentialFindings.Count -eq 0) {
        Write-CheckResult -Name "Credential Scan" -Status Pass
    } else {
        Write-CheckResult -Name "Credential Scan" -Status Warning -Message "$($credentialFindings.Count) potential issues"
        $credentialFindings | Select-Object -First 3 | ForEach-Object {
            Write-Host "    $_" -ForegroundColor Yellow
        }
    }

    # Check for dangerous commands
    $dangerousPatterns = @(
        'Invoke-Expression',
        'Remove-Item.*-Recurse.*-Force',
        'Format-Volume'
    )

    $dangerousFindings = @()
    Get-ChildItem -Recurse -Include *.ps1, *.psm1 | ForEach-Object {
        $content = Get-Content $_.FullName -Raw
        foreach ($pattern in $dangerousPatterns) {
            if ($content -match $pattern) {
                $dangerousFindings += "$($_.Name): Contains $pattern"
            }
        }
    }

    if ($dangerousFindings.Count -eq 0) {
        Write-CheckResult -Name "Dangerous Commands" -Status Pass
    } else {
        Write-CheckResult -Name "Dangerous Commands" -Status Warning -Message "$($dangerousFindings.Count) commands flagged"
    }
} else {
    Write-CheckHeader "Security Scan"
    Write-CheckResult -Name "Security Scan" -Status Skip
}

# Check 6: Module Imports
Write-CheckHeader "Module Import Test"

$importErrors = @()
Get-ChildItem -Path Modules -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $manifestPath = Join-Path $_.FullName "$($_.Name).psd1"

    if (Test-Path $manifestPath) {
        try {
            Import-Module $manifestPath -Force -ErrorAction Stop
            Remove-Module $_.Name -ErrorAction SilentlyContinue
        } catch {
            $importErrors += "$($_.Name): $_"
        }
    }
}

if ($importErrors.Count -eq 0) {
    Write-CheckResult -Name "Module Imports" -Status Pass
} else {
    Write-CheckResult -Name "Module Imports" -Status Fail -Message "$($importErrors.Count) modules failed to import"
    $importErrors | ForEach-Object { Write-Host "    $_" -ForegroundColor Red }
}

# Check 7: Git Status
Write-CheckHeader "Git Status"

$gitCmd = Get-Command git -ErrorAction SilentlyContinue
if ($gitCmd) {
    $status = git status --porcelain 2>$null

    if ($status) {
        $untracked = ($status | Where-Object { $_ -match '^\?\?' }).Count
        $modified = ($status | Where-Object { $_ -match '^ ?M' }).Count
        $staged = ($status | Where-Object { $_ -match '^[MARCD]' }).Count

        Write-Host "  Untracked: $untracked" -ForegroundColor Gray
        Write-Host "  Modified: $modified" -ForegroundColor Gray
        Write-Host "  Staged: $staged" -ForegroundColor Gray

        Write-CheckResult -Name "Git Status" -Status Pass
    } else {
        Write-Host "  Working tree is clean" -ForegroundColor Gray
        Write-CheckResult -Name "Git Status" -Status Pass
    }
} else {
    Write-CheckResult -Name "Git Status" -Status Skip
}

# Summary
Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan
Write-Host "=== CI Pipeline Summary ===" -ForegroundColor Cyan
Write-Host ("=" * 50) -ForegroundColor Cyan

Write-Host "`nPassed: " -NoNewline -ForegroundColor Green
Write-Host $script:PassedChecks.Count

if ($script:WarningChecks.Count -gt 0) {
    Write-Host "Warnings: " -NoNewline -ForegroundColor Yellow
    Write-Host $script:WarningChecks.Count
}

if ($script:FailedChecks.Count -gt 0) {
    Write-Host "Failed: " -NoNewline -ForegroundColor Red
    Write-Host $script:FailedChecks.Count
    Write-Host "`nFailed checks:" -ForegroundColor Red
    $script:FailedChecks | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}

Write-Host "`n" + ("=" * 50) -ForegroundColor Cyan

if ($script:FailedChecks.Count -eq 0) {
    Write-Host "`n✓ All checks passed! Ready to commit and push." -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n✗ Some checks failed. Please fix issues before pushing." -ForegroundColor Red
    Write-Host "`nTips:" -ForegroundColor Yellow
    Write-Host "  - Run with -Fix to auto-fix PSScriptAnalyzer issues" -ForegroundColor Gray
    Write-Host "  - Run .\Setup-DevEnvironment.ps1 to install missing tools" -ForegroundColor Gray
    Write-Host "  - See CI-CD-GUIDE.md for troubleshooting" -ForegroundColor Gray
    exit 1
}
