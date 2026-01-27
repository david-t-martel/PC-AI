#Requires -Version 5.1

<#
.SYNOPSIS
  Generate documentation/status reports using ast-grep (sg) with rg fallback.

.DESCRIPTION
  Scans the repo for TODO/FIXME/INCOMPLETE/@status/DEPRECATED markers and writes:
  - Reports\DOC_STATUS.json (raw sg json when available)
  - Reports\DOC_STATUS.md (human summary + matches)
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $scriptRoot
}

$reportDir = Join-Path $RepoRoot 'Reports'
if (-not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$docStatusJson = Join-Path $reportDir 'DOC_STATUS.json'
$docStatusMd = Join-Path $reportDir 'DOC_STATUS.md'

$markers = 'TODO|FIXME|INCOMPLETE|@status|DEPRECATED'
$rgArgs = @(
    '-n', '-S', $markers, $RepoRoot,
    '-g', '!**/.git/**',
    '-g', '!**/node_modules/**',
    '-g', '!**/bin/**',
    '-g', '!**/obj/**',
    '-g', '!**/target/**',
    '-g', '!**/dist/**'
)

$entries = @()
$entryIndex = @{}
$sgJson = $null

$sgExe = Get-Command sg.exe -ErrorAction SilentlyContinue
if ($sgExe) {
    try {
        $sgArgs = @('scan', '-c', (Join-Path $RepoRoot 'sgconfig.yml'), '--json=compact')
        $sgOutput = & $sgExe.Path @sgArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and $sgOutput) {
            $sgJson = $sgOutput | ConvertFrom-Json
            $sgOutput | Set-Content -Path $docStatusJson -Encoding UTF8
            $sgMatches = $null
            if ($sgJson -is [System.Collections.IEnumerable] -and -not ($sgJson -is [string]) -and -not ($sgJson.PSObject.Properties.Name -contains 'matches')) {
                $sgMatches = $sgJson
            } elseif ($sgJson.matches) {
                $sgMatches = $sgJson.matches
            }
            if ($sgMatches) {
                foreach ($m in $sgMatches) {
                    $key = "$($m.file)|$($m.line)|$($m.text)"
                    if (-not $entryIndex.ContainsKey($key)) {
                        $entryIndex[$key] = $true
                        $entries += [PSCustomObject]@{
                            Path = $m.file
                            Line = $m.line
                            Match = $m.text
                        }
                    }
                }
            }
        }
    }
    catch {
        $sgJson = $null
    }
}

$rgOut = & rg @rgArgs
if ($LASTEXITCODE -eq 0 -and $rgOut) {
    foreach ($line in $rgOut) {
        $parts = $line -split ':', 3
        if ($parts.Count -ge 3) {
            $key = "$($parts[0])|$($parts[1])|$($parts[2].Trim())"
            if (-not $entryIndex.ContainsKey($key)) {
                $entryIndex[$key] = $true
                $entries += [PSCustomObject]@{
                    Path = $parts[0]
                    Line = $parts[1]
                    Match = $parts[2].Trim()
                }
            }
        }
    }
}

$counts = $entries | Group-Object -Property {
    if ($_.Match -match 'TODO') { 'TODO' }
    elseif ($_.Match -match 'FIXME') { 'FIXME' }
    elseif ($_.Match -match 'INCOMPLETE') { 'INCOMPLETE' }
    elseif ($_.Match -match '@status') { '@status' }
    elseif ($_.Match -match 'DEPRECATED') { 'DEPRECATED' }
    else { 'Other' }
}

$md = New-Object System.Text.StringBuilder
$null = $md.AppendLine("# DOC_STATUS")
$null = $md.AppendLine("")
$null = $md.AppendLine("Generated: $timestamp")
$null = $md.AppendLine("")
$null = $md.AppendLine("## Counts")
foreach ($c in $counts) {
    $null = $md.AppendLine("- $($c.Name): $($c.Count)")
}
$null = $md.AppendLine("")
$null = $md.AppendLine("## Matches")
foreach ($e in $entries) {
    $null = $md.AppendLine("- $($e.Path):$($e.Line) $($e.Match)")
}

$md.ToString() | Set-Content -Path $docStatusMd -Encoding UTF8

Write-Host "Wrote: $docStatusMd" -ForegroundColor Green
if ($sgJson) {
    Write-Host "Wrote: $docStatusJson" -ForegroundColor Green
}
