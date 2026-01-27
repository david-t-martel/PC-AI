#Requires -Version 5.1

<#+
.SYNOPSIS
  Auto-fills missing .PARAMETER blocks in PowerShell help comments.

.DESCRIPTION
  Scans Public functions in Modules, compares parameter lists, and inserts
  missing .PARAMETER sections into the nearest comment-based help block.
  If no help block exists, generates a minimal help block above the function.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $scriptRoot
}

function Get-FunctionInfos {
    param([string]$Path)
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    $infos = @()
    foreach ($func in $functions) {
        $parent = $func.Parent
        $nested = $false
        while ($parent) {
            if ($parent -is [System.Management.Automation.Language.FunctionDefinitionAst]) {
                $nested = $true
                break
            }
            $parent = $parent.Parent
        }
        if ($nested) { continue }
        $paramNames = @()
        if ($func.Body -and $func.Body.ParamBlock) {
            foreach ($p in $func.Body.ParamBlock.Parameters) {
                if ($p.Name -and $p.Name.VariablePath) {
                    $paramNames += $p.Name.VariablePath.UserPath
                }
            }
        }
        $infos += [PSCustomObject]@{
            Name = $func.Name
            Parameters = $paramNames
            StartLine = $func.Extent.StartLineNumber
        }
    }
    return $infos
}

function Find-HelpBlockBounds {
    param(
        [string[]]$Lines,
        [int]$FuncLineIndex
    )

    $i = $FuncLineIndex - 1
    while ($i -ge 0 -and $Lines[$i].Trim() -eq '') { $i-- }
    if ($i -lt 0) { return $null }

    if ($Lines[$i].Trim() -ne '#>') { return $null }
    $endIndex = $i
    $i--
    while ($i -ge 0) {
        if ($Lines[$i].Trim() -eq '<#') {
            return [PSCustomObject]@{ Start = $i; End = $endIndex }
        }
        $i--
    }
    return $null
}

function Update-HelpLines {
    param(
        [string[]]$HelpLines,
        [string[]]$MissingParameters
    )

    if (-not $MissingParameters -or $MissingParameters.Count -eq 0) { return $HelpLines }

    $insertIndex = $HelpLines.Length
    for ($i = 0; $i -lt $HelpLines.Length; $i++) {
        if ($HelpLines[$i] -match '^\s*\.EXAMPLE') {
            $insertIndex = $i
            break
        }
    }

    $insertLines = @()
    foreach ($param in $MissingParameters) {
        $insertLines += ".PARAMETER $param"
        $insertLines += "    (auto-generated)"
        $insertLines += ""
    }

    $before = if ($insertIndex -gt 0) { $HelpLines[0..($insertIndex - 1)] } else { @() }
    $after = if ($insertIndex -lt $HelpLines.Length) { $HelpLines[$insertIndex..($HelpLines.Length - 1)] } else { @() }
    return @($before + $insertLines + $after)
}

function Build-HelpBlockLines {
    param(
        [string]$FunctionName,
        [string[]]$Parameters
    )

    $lines = @()
    $lines += '<#'
    $lines += '.SYNOPSIS'
    $lines += "    Auto-generated help for $FunctionName"
    $lines += ''
    $lines += '.DESCRIPTION'
    $lines += "    Auto-generated help. Review and update this description for $FunctionName."
    $lines += ''
    foreach ($param in $Parameters) {
        $lines += ".PARAMETER $param"
        $lines += "    (auto-generated)"
        $lines += ''
    }
    $lines += '.EXAMPLE'
    $lines += "    $FunctionName"
    $lines += '    (auto-generated)'
    $lines += '#>'
    return $lines
}

$modulesRoot = Join-Path $RepoRoot 'Modules'
$publicFiles = Get-ChildItem -Path $modulesRoot -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Public\\' }

foreach ($file in $publicFiles) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $lines = $content -split "`r?`n"
    $functions = Get-FunctionInfos -Path $file.FullName
    if (-not $functions) { continue }

    $functions = $functions | Sort-Object StartLine -Descending

    foreach ($func in $functions) {
        $lineIndex = $func.StartLine - 1
        if ($lineIndex -lt 0 -or $lineIndex -ge $lines.Length) { continue }

        $bounds = Find-HelpBlockBounds -Lines $lines -FuncLineIndex $lineIndex
        if ($bounds) {
            $helpLines = $lines[$bounds.Start..$bounds.End]
            $helpBody = $helpLines -join "`r`n"
            $helpParams = @()
            $paramMatches = [regex]::Matches($helpBody, '(?ms)^\s*\.PARAMETER\s+([^\s]+)')
            foreach ($pm in $paramMatches) { $helpParams += $pm.Groups[1].Value }

            $missing = @($func.Parameters | Where-Object { $helpParams -notcontains $_ })
            if ($missing.Count -gt 0) {
                $updated = Update-HelpLines -HelpLines $helpLines -MissingParameters $missing
                $lines = @($lines[0..($bounds.Start - 1)] + $updated + $lines[($bounds.End + 1)..($lines.Length - 1)])
            }
        } else {
            $newHelp = Build-HelpBlockLines -FunctionName $func.Name -Parameters $func.Parameters
            $lines = @($lines[0..($lineIndex - 1)] + $newHelp + $lines[$lineIndex..($lines.Length - 1)])
        }
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would update $($file.FullName)" -ForegroundColor Yellow
    } else {
        $updatedContent = $lines -join "`r`n"
        Set-Content -Path $file.FullName -Value $updatedContent -Encoding UTF8
        Write-Host "Updated $($file.FullName)" -ForegroundColor Green
    }
}
