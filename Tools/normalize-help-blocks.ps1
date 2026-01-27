#Requires -Version 5.1

<#+
.SYNOPSIS
  Normalize comment-based help blocks for public functions.

.DESCRIPTION
  Ensures each top-level public function has a single well-formed help block.
  Preserves existing non-auto-generated help and inserts missing .PARAMETER
  entries. Rebuilds malformed or auto-generated blocks.
#>

[CmdletBinding()]
param(
    [string]$RepoRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot) {
    $RepoRoot = Split-Path -Parent $scriptRoot
}

function Get-TopLevelFunctions {
    param([string]$Path)

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    $top = @()
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
        $params = @()
        if ($func.Body -and $func.Body.ParamBlock) {
            foreach ($p in $func.Body.ParamBlock.Parameters) {
                if ($p.Name -and $p.Name.VariablePath) {
                    $params += $p.Name.VariablePath.UserPath
                }
            }
        }
        $top += [PSCustomObject]@{
            Name = $func.Name
            StartOffset = $func.Extent.StartOffset
            Parameters = $params
        }
    }
    return $top
}

function Find-HelpBlockBounds {
    param(
        [string]$Content,
        [int]$FunctionOffset
    )

    $before = $Content.Substring(0, $FunctionOffset)
    $lastClose = $before.LastIndexOf('#>')
    if ($lastClose -lt 0) { return $null }

    $afterClose = $before.Substring($lastClose + 2)
    if ($afterClose -notmatch '^\s*$') { return $null }

    $lastOpen = $before.LastIndexOf('<#')
    if ($lastOpen -lt 0 -or $lastOpen -gt $lastClose) { return $null }

    return [PSCustomObject]@{ Start = $lastOpen; End = $lastClose + 2 }
}

function Insert-MissingParameters {
    param(
        [string]$HelpBlock,
        [string[]]$Parameters
    )

    $helpParams = @()
    $paramMatches = [regex]::Matches($HelpBlock, '(?ms)^\s*\.PARAMETER\s+([^\s]+)')
    foreach ($pm in $paramMatches) { $helpParams += $pm.Groups[1].Value }

    $missing = @($Parameters | Where-Object { $helpParams -notcontains $_ })
    if ($missing.Count -eq 0) { return $HelpBlock }

    $lines = $HelpBlock -split "`r?`n"
    $insertIndex = $lines.Length
    for ($i = 0; $i -lt $lines.Length; $i++) {
        if ($lines[$i] -match '^\s*\.EXAMPLE') { $insertIndex = $i; break }
    }

    $insertLines = @()
    foreach ($param in $missing) {
        $insertLines += ".PARAMETER $param"
        $insertLines += "    (auto-generated)"
        $insertLines += ""
    }

    $before = if ($insertIndex -gt 0) { $lines[0..($insertIndex - 1)] } else { @() }
    $after = if ($insertIndex -lt $lines.Length) { $lines[$insertIndex..($lines.Length - 1)] } else { @() }
    return @($before + $insertLines + $after) -join "`r`n"
}

function Build-HelpBlock {
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
    return $lines -join "`r`n"
}

$modulesRoot = Join-Path $RepoRoot 'Modules'
$publicFiles = Get-ChildItem -Path $modulesRoot -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -match '\\Public\\' }

foreach ($file in $publicFiles) {
    $content = Get-Content -Path $file.FullName -Raw -Encoding UTF8
    $functions = Get-TopLevelFunctions -Path $file.FullName | Sort-Object StartOffset -Descending
    if (-not $functions) { continue }

    foreach ($func in $functions) {
        $bounds = Find-HelpBlockBounds -Content $content -FunctionOffset $func.StartOffset
        $helpBlock = $null
        if ($bounds) {
            $helpBlock = $content.Substring($bounds.Start, $bounds.End - $bounds.Start)
            $helpText = $helpBlock.Substring(2, $helpBlock.Length - 4)
            $isAuto = $helpText -match 'Auto-generated help'

            if ($isAuto) {
                $newHelp = Build-HelpBlock -FunctionName $func.Name -Parameters $func.Parameters
            } else {
                $updated = Insert-MissingParameters -HelpBlock $helpText -Parameters $func.Parameters
                $newHelp = '<#' + $updated + '#>'
            }

            $content = $content.Substring(0, $bounds.Start) + $newHelp + $content.Substring($bounds.End)
        } else {
            $newHelp = Build-HelpBlock -FunctionName $func.Name -Parameters $func.Parameters
            $content = $content.Substring(0, $func.StartOffset) + $newHelp + "`r`n" + $content.Substring($func.StartOffset)
        }
    }

    Set-Content -Path $file.FullName -Value $content -Encoding UTF8
}
