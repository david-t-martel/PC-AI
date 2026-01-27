#Requires -Version 5.1

<#!
.SYNOPSIS
    PC-AI CLI utilities (dynamic help extraction)
#>

$script:ModuleRoot = $PSScriptRoot
$script:ProjectRoot = Split-Path -Parent (Split-Path -Parent $script:ModuleRoot)
$script:HelpExtractorType = $null

function Get-PcaiHelpExtractorType {
    if ($script:HelpExtractorType) { return $script:HelpExtractorType }

    $binPath = Join-Path $script:ProjectRoot 'bin\PcaiNative.dll'
    if (-not (Test-Path $binPath)) { return $null }

    try {
        Add-Type -Path $binPath -ErrorAction Stop | Out-Null
        $type = [PcaiNative.HelpExtractor]
        $script:HelpExtractorType = $type
        return $type
    } catch {
        return $null
    }
}

function Get-PCCommandMap {
    [CmdletBinding()]
    param([string]$ProjectRoot)

    $root = if ($ProjectRoot) { $ProjectRoot } else { $script:ProjectRoot }
    $modulesRoot = Join-Path $root 'Modules'
    if (-not (Test-Path $modulesRoot)) { return @{} }

    $map = @{}
    $manifests = Get-ChildItem -Path $modulesRoot -Filter '*.psd1' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.DirectoryName -notmatch '\\Archive(\\|$)' }

    foreach ($manifest in $manifests) {
        try {
            $data = Import-PowerShellDataFile -Path $manifest.FullName
        } catch {
            continue
        }
        $moduleName = Split-Path -Leaf (Split-Path -Parent $manifest.FullName)
        $commands = $data.PrivateData.PCAI.Commands
        if (-not $commands) { continue }
        foreach ($command in $commands) {
            if (-not $map.ContainsKey($command)) {
                $map[$command] = @()
            }
            if (-not ($map[$command] -contains $moduleName)) {
                $map[$command] += $moduleName
            }
        }
    }

    foreach ($baseCommand in @('help', 'version')) {
        if (-not $map.ContainsKey($baseCommand)) {
            $map[$baseCommand] = @()
        }
    }

    return $map
}

function Get-PCCommandModules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$CommandName,
        [string]$ProjectRoot
    )

    $map = Get-PCCommandMap -ProjectRoot $ProjectRoot
    return $map[$CommandName]
}

function Get-PCCommandList {
    [CmdletBinding()]
    param([string]$ProjectRoot)

    $map = Get-PCCommandMap -ProjectRoot $ProjectRoot
    return $map.Keys | Sort-Object
}

function Convert-HelpBlockToEntry {
    param(
        [Parameter(Mandatory)]
        [string]$HelpBlock,
        [Parameter(Mandatory)]
        [string]$FunctionName,
        [Parameter(Mandatory)]
        [string]$SourcePath
    )

    $synopsis = ''
    $description = ''
    $parameterHelp = @{}
    $examples = @()

    if ($HelpBlock -match '(?ms)^\s*\.SYNOPSIS\s*(?<syn>.+?)(?=^\s*\.[A-Z]|\z)') {
        $synopsis = $Matches['syn'].Trim()
    }
    if ($HelpBlock -match '(?ms)^\s*\.DESCRIPTION\s*(?<desc>.+?)(?=^\s*\.[A-Z]|\z)') {
        $description = $Matches['desc'].Trim()
    }
    $paramMatches = [regex]::Matches($HelpBlock, '(?ms)^\s*\.PARAMETER\s+(?<name>\S+)\s*(?<desc>.+?)(?=^\s*\.[A-Z]|\z)')
    foreach ($paramMatch in $paramMatches) {
        $paramName = $paramMatch.Groups['name'].Value.Trim()
        $paramDesc = $paramMatch.Groups['desc'].Value.Trim()
        if ($paramName) {
            $parameterHelp[$paramName] = $paramDesc
        }
    }
    $exampleMatches = [regex]::Matches($HelpBlock, '(?ms)^\s*\.EXAMPLE\s*(?<example>.+?)(?=^\s*\.[A-Z]|\z)')
    foreach ($exampleMatch in $exampleMatches) {
        $exampleText = $exampleMatch.Groups['example'].Value.Trim()
        if ($exampleText) {
            $examples += $exampleText
        }
    }

    return [PSCustomObject]@{
        Name = $FunctionName
        Synopsis = $synopsis
        Description = $description
        SourcePath = $SourcePath
        ParameterHelp = $parameterHelp
        Examples = $examples
    }
}

function Get-FunctionDefinitions {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
    $functions = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

    $defs = @()
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
        $defs += [PSCustomObject]@{
            Name = $func.Name
            Parameters = $paramNames
        }
    }
    return $defs
}

function Get-HelpEntriesFromFiles {
    param(
        [Parameter(Mandatory)]
        [string[]]$Paths
    )

    $entries = @()
    $pattern = '(?s)<#(.*?)#>\s*function\s+([A-Za-z0-9_-]+)'
    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) { continue }
        $defs = Get-FunctionDefinitions -Path $path
        $helpByName = @{}

        $extractor = Get-PcaiHelpExtractorType
        if ($extractor) {
            try {
                $nativeEntries = $extractor::ExtractFromFile($path)
                foreach ($nativeEntry in $nativeEntries) {
                    $nativeParamHelp = @{}
                    $hasParamProperty = $nativeEntry.PSObject.Properties.Name -contains 'Parameters'
                    if ($hasParamProperty -and $nativeEntry.Parameters) {
                        foreach ($key in $nativeEntry.Parameters.Keys) {
                            $nativeParamHelp[$key] = $nativeEntry.Parameters[$key]
                        }
                    }

                    $nativeExamples = @()
                    $hasExamplesProperty = $nativeEntry.PSObject.Properties.Name -contains 'Examples'
                    if ($hasExamplesProperty -and $nativeEntry.Examples) {
                        foreach ($example in $nativeEntry.Examples) {
                            if ($example) {
                                $nativeExamples += $example
                            }
                        }
                    }

                    $helpByName[$nativeEntry.Name] = [PSCustomObject]@{
                        Name = $nativeEntry.Name
                        Synopsis = $nativeEntry.Synopsis
                        Description = $nativeEntry.Description
                        SourcePath = $nativeEntry.SourcePath
                        ParameterHelp = $nativeParamHelp
                        Examples = $nativeExamples
                    }
                }
            } catch {
                # ignore and fall back to regex
            }
        }

        $content = Get-Content -Path $path -Raw -Encoding UTF8
        $matches = [regex]::Matches($content, $pattern)
        foreach ($match in $matches) {
            $helpBlock = $match.Groups[1].Value
            $funcName = $match.Groups[2].Value
            $entry = Convert-HelpBlockToEntry -HelpBlock $helpBlock -FunctionName $funcName -SourcePath $path
            if (-not $helpByName.ContainsKey($funcName)) {
                $helpByName[$funcName] = $entry
                continue
            }

            $existing = $helpByName[$funcName]
            if (-not $existing.Synopsis -and $entry.Synopsis) {
                $existing.Synopsis = $entry.Synopsis
            }
            if (-not $existing.Description -and $entry.Description) {
                $existing.Description = $entry.Description
            }
            if ($entry.ParameterHelp -and $entry.ParameterHelp.Count -gt 0) {
                foreach ($key in $entry.ParameterHelp.Keys) {
                    if (-not $existing.ParameterHelp.ContainsKey($key)) {
                        $existing.ParameterHelp[$key] = $entry.ParameterHelp[$key]
                    }
                }
            }
            if ($entry.Examples -and $entry.Examples.Count -gt 0 -and (-not $existing.Examples -or $existing.Examples.Count -eq 0)) {
                $existing.Examples = $entry.Examples
            }
        }

        foreach ($def in $defs) {
            $entry = $null
            if ($helpByName.ContainsKey($def.Name)) {
                $entry = $helpByName[$def.Name]
            } else {
                $entry = [PSCustomObject]@{
                    Name = $def.Name
                    Synopsis = ''
                    Description = ''
                    SourcePath = $path
                    ParameterHelp = @{}
                }
            }

            $entries += [PSCustomObject]@{
                Name = $entry.Name
                Synopsis = $entry.Synopsis
                Description = $entry.Description
                SourcePath = $entry.SourcePath
                Parameters = $def.Parameters
                ParameterHelp = $entry.ParameterHelp
                Examples = $entry.Examples
            }
        }
    }
    return $entries
}

function Get-PCModuleHelpIndex {
    [CmdletBinding()]
    param(
        [string[]]$Modules,
        [string]$ProjectRoot
    )

    $root = if ($ProjectRoot) { $ProjectRoot } else { $script:ProjectRoot }
    $modulesRoot = Join-Path $root 'Modules'
    if (-not (Test-Path $modulesRoot)) { return @() }

    if (-not $Modules -or $Modules.Count -eq 0) {
        $Modules = Get-ChildItem -Path $modulesRoot -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name
    }

    $allEntries = @()
    foreach ($moduleName in $Modules) {
        $modulePath = Join-Path $modulesRoot $moduleName
        $publicPath = Join-Path $modulePath 'Public'
        if (-not (Test-Path $publicPath)) { continue }

        $files = Get-ChildItem -Path $publicPath -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        if (-not $files) { continue }

        $entries = Get-HelpEntriesFromFiles -Paths $files
        foreach ($entry in $entries) {
            $allEntries += [PSCustomObject]@{
                Module = $moduleName
                Name = $entry.Name
                Synopsis = $entry.Synopsis
                Description = $entry.Description
                SourcePath = $entry.SourcePath
                Parameters = $entry.Parameters
                Examples = $entry.Examples
            }
        }
    }

    return $allEntries
}

function Get-PCCommandSummary {
    [CmdletBinding()]
    param([string]$ProjectRoot)

    $root = if ($ProjectRoot) { $ProjectRoot } else { $script:ProjectRoot }
    $modulesRoot = Join-Path $root 'Modules'
    if (-not (Test-Path $modulesRoot)) { return @() }

    $map = Get-PCCommandMap -ProjectRoot $root
    $summaries = @()

    foreach ($command in ($map.Keys | Sort-Object)) {
        $modules = $map[$command]
        $descriptions = @()

        foreach ($moduleName in $modules) {
            $manifest = Join-Path $modulesRoot $moduleName "$moduleName.psd1"
            if (-not (Test-Path $manifest)) { continue }
            try {
                $data = Import-PowerShellDataFile -Path $manifest
                if ($data.Description) {
                    $descriptions += $data.Description.Trim()
                }
            } catch {
                continue
            }
        }

        $summaries += [PSCustomObject]@{
            Command = $command
            Modules = $modules
            Description = ($descriptions -join ' ')
        }
    }

    return $summaries
}

function Resolve-PCArguments {
    [CmdletBinding()]
    param(
        [string[]]$InputArgs,
        [hashtable]$Defaults = @{}
    )

    return Parse-PCArguments -InputArgs $InputArgs -Defaults $Defaults
}

function Get-PCModuleHelpEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        [string[]]$Modules,
        [string]$ProjectRoot
    )

    $entries = Get-PCModuleHelpIndex -Modules $Modules -ProjectRoot $ProjectRoot
    return $entries | Where-Object { $_.Name -eq $Name -or $_.Module -eq $Name }
}

function Parse-PCArguments {
    [CmdletBinding()]
    param(
        [string[]]$InputArgs,
        [hashtable]$Defaults = @{}
    )

    $parsed = @{
        SubCommand = $null
        Flags = @{}
        Values = @{}
        Positional = @()
    }

    foreach ($key in $Defaults.Keys) {
        $parsed.Values[$key] = $Defaults[$key]
    }

    $i = 0
    while ($i -lt $InputArgs.Count) {
        $arg = $InputArgs[$i]

        if ($arg -match '^--(.+)=(.+)$') {
            $parsed.Values[$Matches[1]] = $Matches[2]
        } elseif ($arg -match '^--(.+)$') {
            $key = $Matches[1]
            if ($i + 1 -lt $InputArgs.Count -and $InputArgs[$i + 1] -notmatch '^-') {
                $parsed.Values[$key] = $InputArgs[$i + 1]
                $i++
            } else {
                $parsed.Flags[$key] = $true
            }
        } elseif ($arg -match '^-([a-zA-Z])$') {
            $parsed.Flags[$Matches[1]] = $true
        } elseif ($null -eq $parsed.SubCommand -and $arg -notmatch '^-') {
            $parsed.SubCommand = $arg
        } else {
            $parsed.Positional += $arg
        }

        $i++
    }

    return $parsed
}

Export-ModuleMember -Function @(
    'Get-PCModuleHelpIndex'
    'Get-PCModuleHelpEntry'
    'Get-PCCommandMap'
    'Get-PCCommandModules'
    'Get-PCCommandList'
    'Get-PCCommandSummary'
    'Parse-PCArguments'
    'Resolve-PCArguments'
)
