#Requires -Version 5.1
<#
.SYNOPSIS
  Generate FunctionGemma tool documentation from pcai-tools.json.

.DESCRIPTION
  Produces a markdown doc that lists tool names, descriptions, parameters,
  and the negative examples used for NO_TOOL routing.
#>

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$ToolsPath,
    [string]$SchemaUtilsPath,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
if (-not $ToolsPath) { $ToolsPath = Join-Path $repoRoot 'Config\pcai-tools.json' }
if (-not $SchemaUtilsPath) { $SchemaUtilsPath = Join-Path $repoRoot 'Deploy\rust-functiongemma-train\src\schema_utils.rs' }
if (-not $OutputPath) { $OutputPath = Join-Path $repoRoot 'Deploy\rust-functiongemma\TOOLS.md' }

$toolsJson = Get-Content $ToolsPath -Raw | ConvertFrom-Json
$tools = @($toolsJson.tools)

$negativeExamples = @()
if (Test-Path $SchemaUtilsPath) {
    $raw = Get-Content $SchemaUtilsPath -Raw
    if ($raw -match '(?s)let prompts = \[(.*?)\];') {
        $block = $Matches[1]
        $matches = [regex]::Matches($block, '"([^"]+)"')
        foreach ($m in $matches) {
            $negativeExamples += $m.Groups[1].Value
        }
    }
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FunctionGemma Tool Catalog")
$lines.Add("")
$lines.Add('Source: `Config/pcai-tools.json`')
$lines.Add("")
$lines.Add("## Tools")

foreach ($tool in $tools) {
    $fn = $tool.function
    $lines.Add("")
    $lines.Add("### $($fn.name)")
    if ($fn.description) { $lines.Add($fn.description) }
    $lines.Add("")
    $lines.Add("Parameters:")
    $params = $fn.parameters
    if (-not $params -or -not $params.properties) {
        $lines.Add("- (none)")
    } else {
        $required = @()
        if ($params.PSObject.Properties.Name -contains 'required') { $required = @($params.required) }
        foreach ($prop in $params.properties.PSObject.Properties) {
            $pName = $prop.Name
            $pSchema = $prop.Value
            $type = if ($pSchema.PSObject.Properties.Name -contains 'type') { $pSchema.type } else { "string" }
            $req = if ($required -contains $pName) { "required" } else { "optional" }
            $enum = if ($pSchema.PSObject.Properties.Name -contains 'enum') { " enum=" + ($pSchema.enum -join ", ") } else { "" }
            $default = if ($pSchema.PSObject.Properties.Name -contains 'default') { " default=" + $pSchema.default } else { "" }
            $lines.Add("- $pName ($type, $req)$enum$default")
        }
    }
}

$lines.Add("")
$lines.Add("## Negative examples (NO_TOOL)")
if ($negativeExamples.Count -gt 0) {
    foreach ($ex in $negativeExamples) {
        $lines.Add("- $ex")
    }
} else {
    $lines.Add("- (none)")
}

$lines.Add("")
$lines.Add("## Notes")
$lines.Add('- Negative examples map to `NO_TOOL` responses.')
$lines.Add('- Keep this file in sync with `Deploy/rust-functiongemma-train/src/schema_utils.rs`.')

$outDir = Split-Path -Parent $OutputPath
if ($outDir -and -not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }

$lines | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "Wrote tool documentation to $OutputPath" -ForegroundColor Green
