<#
.SYNOPSIS
    Generates a prioritized help documentation gaps report
.DESCRIPTION
    Analyzes API signature report to identify functions missing help documentation,
    organized by module with priority ordering
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Read API signature report
$reportPath = Join-Path $PSScriptRoot '..\Reports\API_SIGNATURE_REPORT.json'
$outputPath = Join-Path $PSScriptRoot '..\Reports\HELP_GAPS_PRIORITY.md'

Write-Host "Reading API signature report..."
$report = Get-Content $reportPath -Raw | ConvertFrom-Json

# Extract module name from source path
function Get-ModuleName {
    param([string]$SourcePath)

    if ($SourcePath -match '\\Modules\\([^\\]+)\\') {
        return $matches[1]
    }
    return "Unknown"
}

# Group functions by module
Write-Host "Grouping functions by module..."
$moduleGroups = @{}
$funcList = @($report.PowerShell.MissingHelpParameters)

foreach ($func in $funcList) {
    $moduleName = Get-ModuleName $func.SourcePath

    if (-not $moduleGroups.ContainsKey($moduleName)) {
        $moduleGroups[$moduleName] = [System.Collections.ArrayList]::new()
    }

    [void]$moduleGroups[$moduleName].Add($func)
}

Write-Host "Found $($moduleGroups.Count) modules"

# Calculate statistics
$totalFunctions = $report.PowerShell.FunctionCount
$missingHelp = $report.PowerShell.MissingHelpCount
$coverage = [math]::Round((($totalFunctions - $missingHelp) / $totalFunctions) * 100, 1)

# Build markdown content
$markdown = @"
# Help Documentation Gaps

Generated: $($report.Generated)

## Summary

- **Total functions**: $totalFunctions
- **Missing help**: $missingHelp
- **Coverage**: $coverage%

## Priority Order

"@

# Sort modules: PC-AI.LLM first, then by count of missing params (descending)
Write-Host "Sorting modules..."
$sortedModules = $moduleGroups.GetEnumerator() | ForEach-Object {
    [PSCustomObject]@{
        Name = $_.Key
        Functions = [array]$_.Value
        Count = $_.Value.Count
        Priority = if ($_.Key -eq 'PC-AI.LLM') { 0 } else { 1 }
    }
} | Sort-Object Priority, { -$_.Count }

foreach ($module in $sortedModules) {
    $moduleName = $module.Name
    $functions = $module.Functions

    # Count functions with no help vs partial help
    $noHelp = @($functions | Where-Object { -not $_.HelpPresent }).Count
    $partialHelp = @($functions | Where-Object { $_.HelpPresent }).Count

    $markdown += "`n### $moduleName ($($functions.Count) functions)`n"

    if ($noHelp -gt 0) {
        $markdown += "`n**No help documentation ($noHelp):**`n`n"

        $noHelpFuncs = @($functions | Where-Object { -not $_.HelpPresent } | Sort-Object Name)
        foreach ($func in $noHelpFuncs) {
            $paramCount = @($func.MissingHelpParameters).Count
            $paramList = $func.MissingHelpParameters -join ', '
            $markdown += "- [ ] ``$($func.Name)`` - Missing $paramCount parameters: $paramList`n"
        }
    }

    if ($partialHelp -gt 0) {
        $markdown += "`n**Partial help documentation ($partialHelp):**`n`n"

        $partialHelpFuncs = @($functions | Where-Object { $_.HelpPresent } | Sort-Object Name)
        foreach ($func in $partialHelpFuncs) {
            $paramCount = @($func.MissingHelpParameters).Count
            $paramList = $func.MissingHelpParameters -join ', '
            $markdown += "- [ ] ``$($func.Name)`` - Missing $paramCount parameters: $paramList`n"
        }
    }
}

# Add recommendations section
$markdown += @"

## Recommendations

### High Priority (Complete missing documentation)

1. **PC-AI.LLM module** - Core functionality for LLM integration
   - Focus on `Invoke-LLMChat`, `Invoke-FunctionGemmaReAct`, and routing functions first
   - These are frequently used public interfaces

2. **PC-AI.Cleanup module** - All functions lack documentation
   - `Clear-TempFiles`, `Repair-MachinePath`, `Find-DuplicateFiles` should be documented first

3. **PC-AI.Performance module** - All functions lack documentation
   - `Watch-SystemResources`, `Get-ProcessPerformance` are key diagnostic functions

### Medium Priority (Partial documentation)

1. **PC-AI.Acceleration module** - Multiple functions need completion
   - Helper functions like `Convert-SizeToBytes`, `Format-ByteSize` need documentation
   - Backend implementations (e.g., `Get-ProcessesWithProcs`) can be lower priority

2. **PC-AI.Virtualization module** - Multiple functions need completion
   - Priority: `Install-WSLVsockBridge`, `Start-HVSockProxy` configuration functions
   - Lower: Internal health check helpers like `Get-StatusColor`

### Documentation Standards

When adding help documentation:
- Use comment-based help with `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE`
- Include at least one example showing common usage
- Document parameter validation constraints
- Specify default values where applicable
- Add `.NOTES` section for version history or special requirements

"@

# Write output
Write-Host "Writing report to: $outputPath"
Set-Content -Path $outputPath -Value $markdown -Encoding UTF8

Write-Host ""
Write-Host "Report generated successfully!"
Write-Host ""
Write-Host "Summary:"
Write-Host "  Total functions: $totalFunctions"
Write-Host "  Missing help: $missingHelp"
Write-Host "  Coverage: $coverage%"
Write-Host ""
Write-Host "Modules with missing help:"
foreach ($module in $sortedModules) {
    Write-Host "  $($module.Name): $($module.Count) functions"
}
