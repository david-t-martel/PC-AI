#Requires -Version 5.1

<#+
.SYNOPSIS
  Run PSScriptAnalyzer and export results to Reports\PSSCRIPTANALYZER.json/.md
#>

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $scriptRoot
}

$targetPath = if ($Path) { $Path } else { Join-Path $RepoRoot 'Modules' }

$reportDir = Join-Path $RepoRoot 'Reports'
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$excludePaths = @()
$archivePath = Join-Path $RepoRoot 'Modules\\Archive'
if (Test-Path $archivePath) {
    $excludePaths += $archivePath
}

$files = Get-ChildItem -Path $targetPath -Recurse -Filter '*.ps1' -ErrorAction SilentlyContinue
if ($excludePaths.Count -gt 0) {
    $files = $files | Where-Object {
        $dir = $_.DirectoryName
        $exclude = $false
        foreach ($ex in $excludePaths) {
            if ($dir -like "$ex*") { $exclude = $true; break }
        }
        -not $exclude
    }
}

$filePaths = @($files | Select-Object -ExpandProperty FullName)
$results = @()
foreach ($path in $filePaths) {
    $results += Invoke-ScriptAnalyzer -Path $path -Severity Warning,Error
}

$reportJson = Join-Path $reportDir 'PSSCRIPTANALYZER.json'
$reportMd = Join-Path $reportDir 'PSSCRIPTANALYZER.md'

$results | Select-Object RuleName,Severity,ScriptName,Line,Message | ConvertTo-Json -Depth 4 | Set-Content -Path $reportJson -Encoding UTF8

$md = New-Object System.Text.StringBuilder
$null = $md.AppendLine('# PSSCRIPTANALYZER')
$null = $md.AppendLine('')
$null = $md.AppendLine("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$null = $md.AppendLine('')
foreach ($group in ($results | Group-Object Severity)) {
    $null = $md.AppendLine("## $($group.Name)")
    foreach ($item in $group.Group) {
        $null = $md.AppendLine("- $($item.ScriptName):$($item.Line) [$($item.RuleName)] $($item.Message)")
    }
    $null = $md.AppendLine('')
}

$md.ToString() | Set-Content -Path $reportMd -Encoding UTF8

Write-Host "Wrote: $reportMd" -ForegroundColor Green
Write-Host "Wrote: $reportJson" -ForegroundColor Green
