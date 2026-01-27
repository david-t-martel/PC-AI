<#
.SYNOPSIS
    Runs automated pre-flight checks for the PC_AI ecosystem.

.DESCRIPTION
    Validates integrity of PowerShell, Rust, and C# components.
    Integrates with CargoTools for Rust validation.

.PARAMETER ScriptAnalysis
    Run PSScriptAnalyzer on Modules/

.PARAMETER RustTest
    Run cargo test

.PARAMETER CSharpTest
    Run dotnet test

.PARAMETER Pester
    Run Pester tests

.PARAMETER All
    Run all checks (default if no others specified)
#>
[CmdletBinding()]
param(
	[switch]$ScriptAnalysis,
	[switch]$RustTest,
	[switch]$CSharpTest,
	[switch]$Pester,
	[switch]$StubCheck,
	[switch]$All
)

$ErrorActionPreference = 'Stop'

# Default to All if no specific check selected
if (-not ($ScriptAnalysis -or $RustTest -or $CSharpTest -or $Pester -or $StubCheck)) {
	$All = $true
}

function Write-Section {
	param([string]$Message)
	Write-Host "`n=== $Message ===" -ForegroundColor Cyan
}

function Invoke-Check {
	param([scriptblock]$Action, [string]$Name)
	try {
		& $Action
		Write-Host "[$Name] PASS" -ForegroundColor Green
	} catch {
		Write-Host "[$Name] FAIL: $_" -ForegroundColor Red
		throw "Check failed: $Name"
	}
}

$RootDir = $PSScriptRoot

if ($All -or $ScriptAnalysis) {
	Write-Section 'PSScriptAnalyzer'
	Invoke-Check {
		$results = Invoke-ScriptAnalyzer -Path "$RootDir\Modules" -Recurse -Severity Error, Warning
		if ($results) {
			$results | Format-Table -AutoSize
			# Fail on Errors, warn on keys
			if ($results | Where-Object Severity -EQ 'Error') {
				throw 'PSScriptAnalyzer found errors.'
			}
		}
	} 'ScriptAnalysis'
}

if ($All -or $RustTest) {
	Write-Section 'Rust Tests (Cargo)'
	Invoke-Check {
		Push-Location "$RootDir\Native"
		try {
			if (Get-Module -ListAvailable CargoTools) {
				# Use CargoTools wrapper for preflight
				Invoke-CargoWrapper test --workspace
			} else {
				cargo test --workspace
			}
			if ($LASTEXITCODE -ne 0) { throw 'Cargo test failed' }
		} finally {
			Pop-Location
		}
	} 'RustTest'
}

if ($All -or $CSharpTest) {
	Write-Section 'C# Tests (DotNet)'
	Invoke-Check {
		Push-Location "$RootDir\Native\PcaiNative"
		try {
			dotnet test --nologo
			if ($LASTEXITCODE -ne 0) { throw 'Dotnet test failed' }
		} finally {
			Pop-Location
		}
	} 'CSharpTest'
}

if ($All -or $Pester) {
	Write-Section 'Pester Tests'
	Invoke-Check {
		# Assuming tests are in Tests/
		$TestPath = Join-Path $RootDir 'Tests'
		if (Test-Path $TestPath) {
			Invoke-Pester -Path $TestPath -Output Detailed
		} else {
			Write-Warning 'Tests directory not found.'
		}
	} 'Pester'
}

if ($All -or $StubCheck) {
	Write-Section 'Stub Detection'
	Invoke-Check {
		$patterns = @(
			'throw new NotImplementedException',
			'return NotImplemented',
			'todo!\(',
			'unimplemented!\('
		)

		$files = Get-ChildItem -Path "$RootDir" -Recurse -File -Include *.cs, *.rs, *.ps1 |
			Where-Object { $_.FullName -notmatch '\\(target|bin|obj)\\' -and $_.Name -ne 'Test.ps1' }

		$foundErrors = $false
		foreach ($file in $files) {
			$content = Get-Content $file.FullName -Raw
			foreach ($pattern in $patterns) {
				if ($content -match $pattern) {
					Write-Host "Found stub in $($file.Name): $pattern" -ForegroundColor Red
					$foundErrors = $true
				}
			}
		}

		if ($foundErrors) {
			throw 'Found stubbed/unimplemented code. Please implement or remove.'
		}
	} 'StubDetection'
}

Write-Host "`nAll checks passed!" -ForegroundColor Green
