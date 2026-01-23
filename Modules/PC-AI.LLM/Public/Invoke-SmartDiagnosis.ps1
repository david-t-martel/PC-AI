#Requires -Version 5.1
<#
.SYNOPSIS
    Smart PC diagnosis combining native high-performance tools with Ollama LLM analysis

.DESCRIPTION
    Performs comprehensive PC diagnostics using a hybrid approach:
    1. Native Rust tools for fast data collection (5-15x faster than PowerShell)
    2. Ollama LLM for intelligent analysis and recommendations

    This combines the speed of native code with the reasoning capabilities of
    local LLMs for efficient, private PC diagnostics.

.PARAMETER Path
    Optional path to focus the diagnosis on (e.g., a specific drive or folder)

.PARAMETER AnalysisType
    Type of analysis to perform:
    - Quick: Fast overview of duplicates and disk usage
    - Full: Comprehensive analysis including content search
    - Duplicates: Focus on duplicate file analysis
    - Storage: Focus on disk space and file organization

.PARAMETER Model
    Ollama model to use for analysis (default: qwen2.5-coder:7b)

.PARAMETER SaveReport
    Save the analysis report to a file

.PARAMETER OutputPath
    Path to save the report

.EXAMPLE
    Invoke-SmartDiagnosis -Path "D:\Downloads" -AnalysisType Quick
    Quick diagnostic of Downloads folder

.EXAMPLE
    Invoke-SmartDiagnosis -AnalysisType Duplicates -SaveReport
    Full duplicate analysis with saved report

.OUTPUTS
    PSCustomObject with diagnostic findings and LLM recommendations
#>
function Invoke-SmartDiagnosis {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Position = 0)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Quick', 'Full', 'Duplicates', 'Storage')]
        [string]$AnalysisType = 'Quick',

        [Parameter()]
        [string]$Model = $script:ModuleConfig.DefaultModel,

        [Parameter()]
        [switch]$SaveReport,

        [Parameter()]
        [string]$OutputPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Smart-Diagnosis-Report.txt'),

        [Parameter()]
        [switch]$SkipLLMAnalysis
    )

    $startTime = Get-Date
    Write-Host "`n[Smart Diagnosis] Starting $AnalysisType analysis..." -ForegroundColor Cyan

    # Determine search path
    $searchPath = if ($Path) {
        Resolve-Path $Path -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Path
    } else {
        $env:USERPROFILE
    }

    if (-not $searchPath -or -not (Test-Path $searchPath)) {
        throw "Invalid path: $Path"
    }

    Write-Host "[Smart Diagnosis] Target: $searchPath" -ForegroundColor Gray

    # Collect diagnostic data using native tools
    $diagnosticData = @{
        Path         = $searchPath
        AnalysisType = $AnalysisType
        StartTime    = $startTime
        NativeUsed   = $false
        Results      = @{}
    }

    # Phase 1: Data Collection
    Write-Host "[Phase 1] Collecting diagnostic data..." -ForegroundColor Cyan

    switch ($AnalysisType) {
        'Quick' {
            # Quick: Duplicates + File summary
            Write-Host "  - Scanning for duplicates..." -ForegroundColor Gray
            $diagnosticData.Results.Duplicates = Invoke-NativeSearch -Operation Duplicates -Path $searchPath -MinimumSize 1MB

            Write-Host "  - Scanning file types..." -ForegroundColor Gray
            $diagnosticData.Results.LargeFiles = Invoke-NativeSearch -Operation Files -Path $searchPath -Pattern "*.{zip,rar,7z,iso,exe,msi}" -MaxResults 50
        }

        'Full' {
            # Full: All operations
            Write-Host "  - Scanning for duplicates..." -ForegroundColor Gray
            $diagnosticData.Results.Duplicates = Invoke-NativeSearch -Operation Duplicates -Path $searchPath -MinimumSize 100KB

            Write-Host "  - Scanning file types..." -ForegroundColor Gray
            $diagnosticData.Results.AllFiles = Invoke-NativeSearch -Operation Files -Path $searchPath -Pattern "*" -MaxResults 100

            Write-Host "  - Scanning for potential issues..." -ForegroundColor Gray
            $diagnosticData.Results.Logs = Invoke-NativeSearch -Operation Content -Path $searchPath -Pattern "error|exception|failed" -FilePattern "*.log" -MaxResults 50 -ContextLines 2
        }

        'Duplicates' {
            # Focus on duplicates
            Write-Host "  - Deep duplicate scan..." -ForegroundColor Gray
            $diagnosticData.Results.Duplicates = Invoke-NativeSearch -Operation Duplicates -Path $searchPath -MinimumSize 1KB

            # Also find potential backup duplicates
            Write-Host "  - Scanning backup files..." -ForegroundColor Gray
            $diagnosticData.Results.Backups = Invoke-NativeSearch -Operation Files -Path $searchPath -Pattern "*.{bak,old,backup,~}" -MaxResults 100
        }

        'Storage' {
            # Focus on storage optimization
            Write-Host "  - Scanning large files..." -ForegroundColor Gray
            $diagnosticData.Results.LargeFiles = Invoke-NativeSearch -Operation Files -Path $searchPath -Pattern "*" -MaxResults 200

            Write-Host "  - Scanning temporary files..." -ForegroundColor Gray
            $diagnosticData.Results.TempFiles = Invoke-NativeSearch -Operation Files -Path $searchPath -Pattern "*.{tmp,temp,cache}" -MaxResults 100

            Write-Host "  - Scanning for duplicates..." -ForegroundColor Gray
            $diagnosticData.Results.Duplicates = Invoke-NativeSearch -Operation Duplicates -Path $searchPath -MinimumSize 10MB
        }
    }

    $diagnosticData.NativeUsed = $diagnosticData.Results.Values | ForEach-Object { $_.Engine } | Where-Object { $_ -eq 'Native/Rust' } | Select-Object -First 1
    $diagnosticData.NativeUsed = [bool]$diagnosticData.NativeUsed

    $collectionTime = (Get-Date) - $startTime
    Write-Host "[Phase 1] Data collection complete in $([math]::Round($collectionTime.TotalSeconds, 2))s" -ForegroundColor Green
    Write-Host "  Engine: $(if ($diagnosticData.NativeUsed) { 'Native/Rust (high-performance)' } else { 'PowerShell (fallback)' })" -ForegroundColor $(if ($diagnosticData.NativeUsed) { 'Green' } else { 'Yellow' })

    # Build diagnostic summary for LLM
    $diagnosticSummary = Build-DiagnosticSummary -DiagnosticData $diagnosticData

    if ($SkipLLMAnalysis) {
        Write-Host "`n[Smart Diagnosis] Skipping LLM analysis (use -SkipLLMAnalysis:$false to enable)" -ForegroundColor Yellow

        $result = [PSCustomObject]@{
            AnalysisType         = $AnalysisType
            Path                 = $searchPath
            NativeEngineUsed     = $diagnosticData.NativeUsed
            CollectionTimeMs     = [math]::Round($collectionTime.TotalMilliseconds, 2)
            DiagnosticSummary    = $diagnosticSummary
            RawResults           = $diagnosticData.Results
            LLMAnalysis          = 'Skipped'
            Timestamp            = $startTime
        }

        return $result
    }

    # Phase 2: LLM Analysis
    Write-Host "`n[Phase 2] Analyzing with Ollama ($Model)..." -ForegroundColor Cyan

    # Verify Ollama connectivity
    if (-not (Test-OllamaConnection)) {
        Write-Warning "Ollama not available. Returning raw diagnostic data."

        return [PSCustomObject]@{
            AnalysisType         = $AnalysisType
            Path                 = $searchPath
            NativeEngineUsed     = $diagnosticData.NativeUsed
            CollectionTimeMs     = [math]::Round($collectionTime.TotalMilliseconds, 2)
            DiagnosticSummary    = $diagnosticSummary
            RawResults           = $diagnosticData.Results
            LLMAnalysis          = 'Ollama unavailable'
            Timestamp            = $startTime
        }
    }

    # Build LLM prompt
    $systemPrompt = @"
You are a Windows PC diagnostics expert. Analyze the following diagnostic data and provide:

1. **Summary**: Key findings in 2-4 bullet points
2. **Issues Found**: Categorize by severity (Critical/High/Medium/Low)
3. **Recommendations**: Specific, actionable steps to address issues
4. **Space Recovery**: Estimate recoverable disk space if applicable

Be concise and technical. Focus on actionable insights.
Format with markdown headers and bullet points.
"@

    $userPrompt = @"
Analyze this PC diagnostic data:

## Analysis Type: $AnalysisType
## Target Path: $searchPath
## Engine: $(if ($diagnosticData.NativeUsed) { 'Native/Rust (high-performance)' } else { 'PowerShell' })

$diagnosticSummary

Provide your analysis and recommendations.
"@

    try {
        $messages = @(
            @{ role = 'system'; content = $systemPrompt }
            @{ role = 'user'; content = $userPrompt }
        )

        $llmResponse = Invoke-OllamaChat -Messages $messages -Model $Model -Temperature 0.3 -TimeoutSeconds 120
        $analysisText = $llmResponse.message.content

        $endTime = Get-Date
        $totalDuration = ($endTime - $startTime).TotalSeconds

        Write-Host "[Phase 2] Analysis complete" -ForegroundColor Green

        # Build result
        $result = [PSCustomObject]@{
            AnalysisType         = $AnalysisType
            Path                 = $searchPath
            NativeEngineUsed     = $diagnosticData.NativeUsed
            CollectionTimeMs     = [math]::Round($collectionTime.TotalMilliseconds, 2)
            AnalysisTimeSeconds  = [math]::Round($totalDuration - $collectionTime.TotalSeconds, 2)
            TotalTimeSeconds     = [math]::Round($totalDuration, 2)
            DiagnosticSummary    = $diagnosticSummary
            LLMAnalysis          = $analysisText
            Model                = $Model
            RawResults           = $diagnosticData.Results
            Timestamp            = $startTime
        }

        # Display analysis
        Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
        Write-Host "SMART DIAGNOSIS ANALYSIS" -ForegroundColor Cyan
        Write-Host "$("=" * 80)`n" -ForegroundColor Cyan
        Write-Host $analysisText
        Write-Host "`n$("=" * 80)" -ForegroundColor Cyan
        Write-Host "Total time: $([math]::Round($totalDuration, 2))s (Collection: $([math]::Round($collectionTime.TotalSeconds, 2))s, Analysis: $([math]::Round($totalDuration - $collectionTime.TotalSeconds, 2))s)" -ForegroundColor Gray

        # Save report if requested
        if ($SaveReport) {
            $reportContent = @"
SMART PC DIAGNOSIS REPORT
Generated: $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))
Analysis Type: $AnalysisType
Target Path: $searchPath
Engine: $(if ($diagnosticData.NativeUsed) { 'Native/Rust' } else { 'PowerShell' })
Model: $Model

$("-" * 80)

DIAGNOSTIC DATA SUMMARY:
$diagnosticSummary

$("-" * 80)

LLM ANALYSIS:
$analysisText

$("-" * 80)

Performance:
- Data Collection: $([math]::Round($collectionTime.TotalMilliseconds, 2)) ms
- LLM Analysis: $([math]::Round($totalDuration - $collectionTime.TotalSeconds, 2)) seconds
- Total Time: $([math]::Round($totalDuration, 2)) seconds
"@

            [System.IO.File]::WriteAllText($OutputPath, $reportContent, [System.Text.Encoding]::UTF8)
            Write-Host "`nReport saved to: $OutputPath" -ForegroundColor Cyan
            $result | Add-Member -MemberType NoteProperty -Name 'ReportSavedTo' -Value $OutputPath
        }

        return $result
    }
    catch {
        Write-Error "LLM analysis failed: $_"
        throw
    }
}

function Build-DiagnosticSummary {
    [CmdletBinding()]
    param($DiagnosticData)

    $summary = [System.Text.StringBuilder]::new()

    foreach ($key in $DiagnosticData.Results.Keys) {
        $result = $DiagnosticData.Results[$key]

        $null = $summary.AppendLine("### $key")

        if ($result.Summary) {
            $null = $summary.AppendLine($result.Summary)
        }

        switch ($key) {
            'Duplicates' {
                if ($result.DuplicateGroups -gt 0) {
                    $null = $summary.AppendLine("- Duplicate groups: $($result.DuplicateGroups)")
                    $null = $summary.AppendLine("- Duplicate files: $($result.DuplicateFiles)")
                    $null = $summary.AppendLine("- Wasted space: $($result.WastedMB) MB ($($result.WastedGB) GB)")

                    if ($result.TopGroups) {
                        $null = $summary.AppendLine("- Top duplicate groups:")
                        foreach ($group in ($result.TopGroups | Select-Object -First 5)) {
                            $null = $summary.AppendLine("  - $($group.Count) files x $($group.SizeMB) MB = $($group.WastedMB) MB wasted")
                        }
                    }
                }
                else {
                    $null = $summary.AppendLine("- No significant duplicates found")
                }
            }

            { $_ -in 'LargeFiles', 'AllFiles', 'Backups', 'TempFiles' } {
                $null = $summary.AppendLine("- Files found: $($result.FilesMatched)")
                $null = $summary.AppendLine("- Total size: $($result.TotalSizeMB) MB")

                if ($result.Files) {
                    $null = $summary.AppendLine("- Sample files:")
                    foreach ($file in ($result.Files | Select-Object -First 5)) {
                        $null = $summary.AppendLine("  - $($file.Path) ($($file.SizeKB) KB)")
                    }
                }
            }

            'Logs' {
                $null = $summary.AppendLine("- Files with issues: $($result.FilesMatched)")
                $null = $summary.AppendLine("- Total matches: $($result.TotalMatches)")

                if ($result.Matches) {
                    $null = $summary.AppendLine("- Sample issues:")
                    foreach ($match in ($result.Matches | Select-Object -First 5)) {
                        $shortPath = Split-Path $match.Path -Leaf
                        $truncatedLine = if ($match.Line.Length -gt 80) { $match.Line.Substring(0, 77) + '...' } else { $match.Line }
                        $null = $summary.AppendLine("  - $shortPath`:$($match.LineNumber): $truncatedLine")
                    }
                }
            }
        }

        $null = $summary.AppendLine("- Elapsed: $($result.ElapsedMs) ms (Engine: $($result.Engine))")
        $null = $summary.AppendLine()
    }

    return $summary.ToString()
}
